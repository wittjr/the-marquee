// Pass-through proxy for the TMDB API so the read token never ships in the web
// bundle. The client calls `/api/tmdb/<path>?<query>` and this function forwards
// to `https://api.themoviedb.org/3/<path>?<query>` with the bearer token from
// the TMDB_READ_TOKEN environment variable.
//
// Image URLs (image.tmdb.org) are public and are NOT proxied — only API calls.

export const config = { path: '/api/tmdb/*' };

const TMDB_BASE = 'https://api.themoviedb.org/3';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('', { status: 204, headers: cors });
  }
  if (req.method !== 'GET') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const token = process.env.TMDB_READ_TOKEN;
  if (!token) {
    return json({ error: 'Server missing TMDB_READ_TOKEN env var' }, 500);
  }

  const url = new URL(req.url);
  const subPath = url.pathname.replace(/^\/api\/tmdb\/?/, '');
  if (!subPath) {
    return json({ error: 'Missing TMDB path' }, 400);
  }

  const target = `${TMDB_BASE}/${subPath}${url.search}`;
  const res = await fetch(target, {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'User-Agent': 'the-marquee/1.0 (+https://github.com/jamiewitt/the-marquee)',
    },
  });

  const text = await res.text();
  return new Response(text, {
    status: res.status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
};

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
