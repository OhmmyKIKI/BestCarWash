// api/proxy.js - High-Capacity Supabase Serverless Proxy for BestCarWash
// Resolves HTTP 494 REQUEST_HEADER_TOO_LARGE and bypasses ISP connection resets

const SUPABASE_URL = 'https://mrmtbzbfmgdfjsrdnzbv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ybXRiemJmbWdkZmpzcmRuemJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzMDE4NDcsImV4cCI6MjEwNDg3Nzg0N30.HXCGJ4byqFdEERHEOo_YaQA2DdF0-AsvRi1F54Uj0eI';

export default async function handler(req, res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', '*');

    if (req.method === 'OPTIONS') {
        return res.status(200).end();
    }

    try {
        const payload = req.method === 'GET' ? req.query : (req.body || {});
        const { endpoint, method = 'GET', body, token, action } = payload;

        // Action: Purge bloated user metadata from Supabase Auth directly from AWS
        if (action === 'purge_metadata' && token) {
            try {
                const purgeRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
                    method: 'PUT',
                    headers: {
                        'apikey': SUPABASE_ANON_KEY,
                        'Authorization': `Bearer ${token}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        data: {
                            cover_image_url: null,
                            shop_images: null,
                            shop_cover: null
                        }
                    })
                });
                const purgeData = await purgeRes.json().catch(() => ({}));
                return res.status(200).json({ ok: true, data: purgeData });
            } catch (pErr) {
                return res.status(200).json({ ok: false, error: pErr.message });
            }
        }

        if (!endpoint || typeof endpoint !== 'string') {
            return res.status(200).json([]);
        }

        // Return empty array for uninitialized query parameters to prevent Postgres 400 Bad Request
        if (endpoint.includes('eq.undefined') || endpoint.includes('eq.null') || endpoint.includes('in.()')) {
            return res.status(200).json([]);
        }

        const cleanEndpoint = endpoint.replace(/^\/+/, '');
        const targetUrl = cleanEndpoint.startsWith('http') 
            ? cleanEndpoint 
            : (cleanEndpoint.startsWith('auth/') ? `${SUPABASE_URL}/${cleanEndpoint}` : `${SUPABASE_URL}/rest/v1/${cleanEndpoint}`);

        const authHeader = token ? `Bearer ${token}` : `Bearer ${SUPABASE_ANON_KEY}`;
        const fetchHeaders = {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': authHeader,
            'Prefer': 'return=representation'
        };

        const reqMethod = (method || 'GET').toUpperCase();
        const fetchOpts = {
            method: reqMethod,
            headers: fetchHeaders
        };

        if (body && ['POST', 'PUT', 'PATCH', 'DELETE'].includes(reqMethod)) {
            fetchHeaders['Content-Type'] = 'application/json';
            fetchOpts.body = typeof body === 'string' ? body : JSON.stringify(body);
        }

        let targetRes = await fetch(targetUrl, fetchOpts);

        // If 400 due to non-existent columns (e.g. cover_image_url or logo_url in schema cache), retry without them
        if (!targetRes.ok && targetRes.status === 400 && body) {
            let retryBody = null;
            try {
                retryBody = typeof body === 'string' ? JSON.parse(body) : { ...body };
            } catch (_) {}

            if (retryBody && typeof retryBody === 'object') {
                let hasRemoved = false;
                ['cover_image_url', 'logo_url', 'city', 'slogan', 'facilities', 'review_count', 'images'].forEach(col => {
                    if (col in retryBody) {
                        delete retryBody[col];
                        hasRemoved = true;
                    }
                });
                if (hasRemoved) {
                    fetchOpts.body = JSON.stringify(retryBody);
                    targetRes = await fetch(targetUrl, fetchOpts);
                }
            }
        }

        const text = await targetRes.text();
        let parsed;
        try {
            parsed = text ? JSON.parse(text) : true;
        } catch (_) {
            parsed = text;
        }

        return res.status(targetRes.status).json(parsed);
    } catch (err) {
        console.error('[proxy.js] error:', err);
        return res.status(500).json({ error: err.message || 'Internal proxy error' });
    }
}
