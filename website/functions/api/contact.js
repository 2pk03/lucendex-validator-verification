// Contact Form Handler
// Turnstile + Honeypot spam protection → Send via iCloud SMTP

export async function onRequestPost({ request, env }) {
  try {
    const ct = request.headers.get('content-type') || '';
    const data = ct.includes('application/json')
      ? await request.json()
      : Object.fromEntries(await request.formData());

    const name = String(data.name || '').trim();
    const email = String(data.email || '').trim();
    const company = String(data.company || '').trim();
    const interest = String(data.interest || '').trim();
    const message = String(data.message || '').trim();
    const website = String(data.website || '');
    const turnstileToken = String(data['cf-turnstile-response'] || data.turnstileToken || '');

    // Honeypot - pretend success
    if (website) {
      return json({ success: true, message: 'Thanks!' }, 200);
    }

    // Validate
    if (!name || !email || !message || !turnstileToken) {
      return json({ error: 'Missing required fields' }, 400);
    }

    // Verify Turnstile
    const ver = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        secret: env.TURNSTILE_SECRET_KEY,
        response: turnstileToken,
        remoteip: request.headers.get('CF-Connecting-IP') || ''
      })
    }).then(r => r.json());

    if (!ver.success) {
      return json({ error: 'Security verification failed', details: ver['error-codes'] || [] }, 400);
    }

    // Compose email
    const emailBody = `New Contact - LucenDEX

Name: ${name}
Email: ${email}
Company: ${company || 'N/A'}
Interest: ${interest}

Message:
${message}

---
IP: ${request.headers.get('CF-Connecting-IP') || 'n/a'}
Time: ${new Date().toISOString()}`;

    // Send via Resend
    const emailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from: 'LucenDEX <noreply@lucendex.com>',
        to: 'hello@lucendex.com',
        reply_to: email,
        subject: `Contact: ${interest} - ${name}`,
        text: emailBody
      })
    });

    if (!emailRes.ok) {
      const errorBody = await emailRes.text();
      console.error('Resend error:', emailRes.status, errorBody);
      return json({ error: 'Failed to send email', details: errorBody }, 500);
    }

    return json({ success: true, message: 'Message sent!' }, 200);
    
  } catch (e) {
    console.error('Error:', e);
    return json({ error: 'Server error', details: String(e?.message || e) }, 500);
  }
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json' }
  });
}
