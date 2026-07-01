// Serverless proxy for Trakt OAuth operations that require the client secret,
// so the secret never ships in the web bundle. The client sends the grant
// params (authorization_code / refresh_token) or { action: 'revoke' }; this
// function adds TRAKT_ID + TRAKT_SECRET (from environment variables) and relays
// to Trakt.
//
// Endpoint: /.netlify/functions/trakt-auth

const TRAKT_TOKEN_URL = 'https://api.trakt.tv/oauth/token';
const TRAKT_REVOKE_URL = 'https://api.trakt.tv/oauth/revoke';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('', { status: 204, headers: cors });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const clientId = process.env.TRAKT_ID;
  const clientSecret = process.env.TRAKT_SECRET;
  if (!clientId || !clientSecret) {
    return json({ error: 'Server missing TRAKT_ID / TRAKT_SECRET env vars' }, 500);
  }

  let body;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  // Trakt is behind Cloudflare, which rejects (403) server-side requests with a
  // missing/default User-Agent. Send a real one plus the standard Trakt headers.
  const traktHeaders = {
    'Content-Type': 'application/json',
    'User-Agent': 'the-marquee/1.0 (+https://github.com/jamiewitt/the-marquee)',
    'trakt-api-version': '2',
    'trakt-api-key': clientId,
  };

  // Revoke an access token.
  if (body.action === 'revoke') {
    await fetch(TRAKT_REVOKE_URL, {
      method: 'POST',
      headers: traktHeaders,
      body: JSON.stringify({
        token: body.token,
        client_id: clientId,
        client_secret: clientSecret,
      }),
    });
    return new Response('', { status: 204, headers: cors });
  }

  // Exchange an authorization code or refresh token for tokens.
  const { grant_type, code, refresh_token, redirect_uri } = body;
  if (grant_type !== 'authorization_code' && grant_type !== 'refresh_token') {
    return json({ error: 'Unsupported grant_type' }, 400);
  }

  const payload = {
    client_id: clientId,
    client_secret: clientSecret,
    grant_type,
    redirect_uri,
  };
  if (grant_type === 'authorization_code') {
    payload.code = code;
  } else {
    payload.refresh_token = refresh_token;
  }

  const traktRes = await fetch(TRAKT_TOKEN_URL, {
    method: 'POST',
    headers: traktHeaders,
    body: JSON.stringify(payload),
  });

  // Relay Trakt's response (token JSON or error) straight through.
  const text = await traktRes.text();
  return new Response(text, {
    status: traktRes.status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
};

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
