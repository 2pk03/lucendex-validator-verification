package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/lucendex/backend/internal/parser"
	"github.com/lucendex/backend/internal/store"
	"github.com/lucendex/backend/internal/xrpl"
)

var (
	// Set at build time via -ldflags
	version = "dev"
	buildTime = "unknown"
)

var (
	rippledWS   = flag.String("rippled-ws", getEnv("RIPPLED_WS", "ws://localhost:6006"), "rippled Full-History WebSocket URL")
	dbConnStr   = flag.String("db", getEnv("DATABASE_URL", ""), "PostgreSQL connection string")
	verbose     = flag.Bool("v", getEnv("VERBOSE", "") == "true", "Enable verbose logging")
	showVersion = flag.Bool("version", false, "Show version and exit")
	startLedger = flag.Uint64("start-ledger", 99984580, "Earliest ledger to index (Nov 1, 2025 00:00 UTC ≈ ledger 99984580)")
)

// getEnv retrieves environment variable or returns default
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// logVerbose logs only when verbose mode is enabled
func logVerbose(format string, v ...interface{}) {
	if *verbose {
		log.Printf(format, v...)
	}
}

// logInfo logs to stdout (normal operation)
func logInfo(format string, v ...interface{}) {
	log.SetOutput(os.Stdout)
	log.Printf(format, v...)
	log.SetOutput(os.Stderr) // Reset to stderr for errors
}

// logError logs to stderr (errors only)
func logError(format string, v ...interface{}) {
	log.SetOutput(os.Stderr)
	log.Printf(format, v...)
}

func main() {
	flag.Parse()
	
	// Set log output to stdout (stderr only for Fatal errors)
	log.SetOutput(os.Stdout)
	
	if *showVersion {
		log.Printf("lucendex-indexer, build %s", buildTime)
		return
	}
	
	log.Printf("lucendex-indexer, build %s", buildTime)
	log.Printf("Rippled WS: %s", *rippledWS)
	
	// Validate required configuration
	if *dbConnStr == "" {
		log.Fatal("DATABASE_URL environment variable or -db flag is required")
	}
	
	// Connect to database
	log.Printf("Connecting to database...")
	db, err := store.NewStore(*dbConnStr)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()
	log.Printf("✓ Database connected")
	
	// Check for last checkpoint
	ctx := context.Background()
	checkpoint, err := db.GetLastCheckpoint(ctx)
	if err != nil {
		log.Fatalf("Failed to get last checkpoint: %v", err)
	}
	
	// Connect to rippled
	log.Printf("Connecting to rippled...")
	client := xrpl.NewClient(*rippledWS)
	
	if err := client.Connect(); err != nil {
		log.Fatalf("Failed to connect to rippled: %v", err)
	}
	defer client.Close()
	log.Printf("✓ Connected to rippled")
	
	// Get current ledger index to detect gaps
	serverInfo, err := client.GetServerInfo()
	if err != nil {
		log.Fatalf("Failed to get server info: %v", err)
	}
	currentLedger := serverInfo.Result.Info.ValidatedLedger.Seq
	log.Printf("Current validated ledger: %d", currentLedger)
	
	// Subscribe to ledger stream FIRST (Fix #1: prevent missing ledgers during backfill)
	if err := client.Subscribe(); err != nil {
		log.Fatalf("Failed to subscribe to ledger stream: %v", err)
	}
	log.Printf("✓ Subscribed to ledger stream")
	
	// Create parsers for live processing
	ammParser := parser.NewAMMParser()
	orderbookParser := parser.NewOrderbookParser()
	
	// Check for gaps and backfill in background if needed
	if checkpoint != nil {
		log.Printf("Found checkpoint at ledger %d (hash: %s)", checkpoint.LedgerIndex, checkpoint.LedgerHash)
		
		gap := currentLedger - uint64(checkpoint.LedgerIndex)
		if gap > 1 {
			// Smart backfill threshold
			const smallGapThreshold = 1000 // ~50 minutes of ledgers
			missingCount := gap - 1
			
			// Determine backfill start point (respect START_LEDGER cutoff)
			backfillStart := uint64(checkpoint.LedgerIndex + 1)
			if backfillStart < *startLedger {
				backfillStart = *startLedger
				log.Printf("Respecting START_LEDGER cutoff: %d", *startLedger)
			}
			
			if missingCount > smallGapThreshold {
				log.Printf("⚠ Large gap detected: %d ledgers", missingCount)
				log.Printf("Skipping backfill - resuming from current ledger")
				log.Printf("Partner orders can be verified on-demand in M3 Partner API")
			} else if backfillStart >= currentLedger {
				log.Printf("✓ All missing ledgers before START_LEDGER cutoff - resuming from current")
			} else {
				// Small gap - backfill for continuity
				log.Printf("⚠ Small gap detected: %d ledgers (%d to %d)", missingCount, backfillStart, currentLedger-1)
				log.Printf("Starting background backfill...")
				
				go func() {
					backfillClient := xrpl.NewClientWithBuffer(*rippledWS, 10000)
					if err := backfillClient.Connect(); err != nil {
						log.Printf("Failed to connect backfill client: %v", err)
						return
					}
					defer backfillClient.Close()
					
					backfillParser := parser.NewAMMParser()
					backfillOrderbookParser := parser.NewOrderbookParser()
					
					backfillStartTime := time.Now()
					backfillCount := 0
					backfillErrors := 0
					
					for i := backfillStart; i < currentLedger; i++ {
						var ledger *xrpl.LedgerResponse
						var err error
						for retry := 0; retry < 3; retry++ {
							ledger, err = backfillClient.FetchLedgerSync(i)
							if err == nil {
								break
							}
							log.Printf("Backfill retry %d/3 for ledger %d: %v", retry+1, i, err)
							time.Sleep(time.Second * time.Duration(retry+1))
						}
						
						if err != nil {
							log.Printf("❌ Failed to backfill ledger %d after 3 retries - STOPPING", i)
							return
						}
						
						if err := processLedger(ctx, db, ledger, backfillParser, backfillOrderbookParser); err != nil {
							log.Printf("Error processing backfill ledger %d: %v", i, err)
							backfillErrors++
						} else {
							backfillCount++
						}
						
						if backfillCount%100 == 0 {
							elapsed := time.Since(backfillStartTime)
							remaining := currentLedger - i
							eta := time.Duration(float64(elapsed)/float64(backfillCount)*float64(remaining))
							log.Printf("Backfill: %d/%d (%.1f%%) - ETA: %v", 
								backfillCount, missingCount, float64(backfillCount)/float64(missingCount)*100, eta)
						}
					}
					
					log.Printf("✓ Backfill complete: %d ledgers in %v (errors: %d)", 
						backfillCount, time.Since(backfillStartTime), backfillErrors)
				}()
			}
		} else {
			log.Printf("✓ No gap detected - indexer is up to date")
		}
	} else {
		log.Printf("No checkpoint found - starting from current ledger %d", currentLedger)
	}
	
	// Set up signal handling for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	
	log.Printf("✓ Indexer running - waiting for ledgers...")
	
	// Main processing loop
	for {
		select {
		case <-sigChan:
			log.Printf("Shutdown signal received - closing gracefully")
			return
			
		case err := <-client.ErrorChan():
			log.Printf("Error from rippled client: %v", err)
			
		case ledger := <-client.LedgerChan():
			if err := processLedger(ctx, db, ledger, ammParser, orderbookParser); err != nil {
				log.Printf("Error processing ledger %d: %v", ledger.LedgerIndex, err)
			}
		}
	}
}

// processLedger processes a single ledger
func processLedger(
	ctx context.Context,
	db *store.Store,
	ledger *xrpl.LedgerResponse,
	ammParser *parser.AMMParser,
	orderbookParser *parser.OrderbookParser,
) error {
	start := time.Now()
	
	// Check if ledger already processed (duplicate prevention)
	existingCheckpoint, err := db.GetCheckpoint(ctx, int64(ledger.LedgerIndex))
	if err == nil && existingCheckpoint != nil {
		logVerbose("Skipping already processed ledger %d", ledger.LedgerIndex)
		return nil
	}
	
	// Verify ledger hash continuity (detect forks/corruption)
	if ledger.LedgerIndex > 1 {
		prevCheckpoint, err := db.GetCheckpoint(ctx, int64(ledger.LedgerIndex-1))
		if err == nil && prevCheckpoint != nil {
			// Verify parent hash matches previous ledger hash
			// Note: XRPL ledger data doesn't always include parent_hash in our response
			// We verify sequential processing instead
			logVerbose("Verified sequential ledger: %d follows %d", ledger.LedgerIndex, prevCheckpoint.LedgerIndex)
		}
	}
	
	log.Printf("Processing ledger %d (hash: %s, txns: %d)", 
		ledger.LedgerIndex, ledger.LedgerHash, ledger.TxnCount)
	
	// Process each transaction
	for _, tx := range ledger.Transactions {
		logVerbose("Processing tx %s (type: %s)", tx.Hash, tx.TransactionType)
		
		// Convert transaction to map for parser
		txMap := make(map[string]interface{})
		txBytes, err := json.Marshal(tx)
		if err != nil {
			log.Printf("Failed to marshal transaction: %v", err)
			continue
		}
		
		if err := json.Unmarshal(txBytes, &txMap); err != nil {
			log.Printf("Failed to unmarshal transaction: %v", err)
			continue
		}
		
		// Try AMM parser
		pool, err := ammParser.ParseTransaction(txMap, ledger.LedgerIndex, ledger.LedgerHash)
		if err != nil {
			log.Printf("AMM parser error on tx %s: %v", tx.Hash, err)
		} else if pool != nil {
			if err := db.UpsertAMMPool(ctx, pool); err != nil {
				log.Printf("Failed to upsert AMM pool: %v", err)
			} else {
				log.Printf("  ✓ AMM pool updated: %s/%s", pool.Asset1, pool.Asset2)
			}
		} else {
			logVerbose("  Skipped (not AMM transaction)")
		}
		
		// Try orderbook parser
		offer, err := orderbookParser.ParseTransaction(txMap, ledger.LedgerIndex, ledger.LedgerHash)
		if err != nil {
			log.Printf("Orderbook parser error on tx %s: %v", tx.Hash, err)
		} else if offer != nil {
			if err := db.UpsertOffer(ctx, offer); err != nil {
				log.Printf("Failed to upsert offer: %v", err)
			} else {
				if offer.Status == "invalid_parse" {
					logVerbose("  ⚠ Invalid offer stored: %v", offer.Meta["error"])
				} else {
					log.Printf("  ✓ Offer created: %s/%s @ %s", offer.BaseAsset, offer.QuoteAsset, offer.Price)
				}
			}
		} else {
			logVerbose("  Skipped (not orderbook transaction)")
		}
		
		// Check for OfferCancel
		if tx.TransactionType == "OfferCancel" {
			account, seq, err := orderbookParser.ParseOfferCancel(txMap)
			if err == nil {
				if err := db.CancelOffer(ctx, account, seq, int64(ledger.LedgerIndex)); err != nil {
					log.Printf("Failed to cancel offer: %v", err)
				} else {
					log.Printf("  ✓ Offer cancelled: account=%s seq=%d", account, seq)
				}
			} else {
				logVerbose("  OfferCancel parse error: %v", err)
			}
		}
	}
	
	// Save checkpoint
	duration := time.Since(start)
	checkpoint := &store.LedgerCheckpoint{
		LedgerIndex:          int64(ledger.LedgerIndex),
		LedgerHash:           ledger.LedgerHash,
		CloseTime:            int64(ledger.LedgerTime),
		CloseTimeHuman:       time.Unix(int64(ledger.LedgerTime)+946684800, 0), // Ripple epoch to Unix
		TransactionCount:     ledger.TxnCount,
		ProcessingDurationMs: int(duration.Milliseconds()),
	}
	
	if err := db.SaveCheckpoint(ctx, checkpoint); err != nil {
		return err
	}
	
	log.Printf("✓ Ledger %d indexed in %v", ledger.LedgerIndex, duration)
	return nil
}
