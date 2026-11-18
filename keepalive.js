/*
  Appel quotidien (voir vercel.json) pour que Supabase ne mette pas le projet en pause.
  Variables à créer dans Vercel : SUPABASE_URL et SUPABASE_ANON_KEY (mêmes valeurs que config.js).
*/
export default async function handler(req, res) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY;
  if (!url || !key) {
    res.status(500).json({ ok: false, erreur: 'Variables SUPABASE_URL / SUPABASE_ANON_KEY manquantes' });
    return;
  }
  const headers = { apikey: key };
  if (key.startsWith('eyJ')) headers.Authorization = 'Bearer ' + key;
  try {
    const r = await fetch(url.replace(/\/$/, '') + '/rest/v1/site_settings?select=key&limit=1', { headers });
    res.status(r.ok ? 200 : 502).json({ ok: r.ok });
  } catch (e) {
    res.status(502).json({ ok: false });
  }
}
