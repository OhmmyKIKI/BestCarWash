// supabase-client.js (auth local copy)
// Supabase Configuration & Resilient Client
var SUPABASE_URL = 'https://mrmtbzbfmgdfjsrdnzbv.supabase.co';
var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ybXRiemJmbWdkZmpzcmRuemJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzMDE4NDcsImV4cCI6MjEwNDg3Nzg0N30.HXCGJ4byqFdEERHEOo_YaQA2DdF0-AsvRi1F54Uj0eI';

function getSupabaseClient() {
    if (window.supabaseClient) return window.supabaseClient;
    if (window.supabase && typeof window.supabase.createClient === 'function') {
        window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
            auth: {
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: true
            }
        });
        return window.supabaseClient;
    }
    return null;
}

var supabaseClient = getSupabaseClient();
var supabase = supabaseClient;
window.supabaseClient = supabaseClient;
window.getSupabaseClient = getSupabaseClient;
window.SUPABASE_URL = SUPABASE_URL;
window.SUPABASE_ANON_KEY = SUPABASE_ANON_KEY;

async function getValidAuthToken() {
    try {
        const client = getSupabaseClient();
        if (client && client.auth) {
            const { data } = await client.auth.getSession().catch(() => ({ data: null }));
            const sess = data?.session;
            if (sess?.access_token) {
                const now = Math.floor(Date.now() / 1000);
                if (sess.expires_at && sess.expires_at > now + 30) {
                    return sess.access_token;
                }
                const refreshRes = await client.auth.refreshSession().catch(() => null);
                if (refreshRes?.data?.session?.access_token) {
                    return refreshRes.data.session.access_token;
                }
            }
        }
    } catch (_) {}

    try {
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && (key.startsWith('sb-') && key.endsWith('-auth-token'))) {
                const parsed = JSON.parse(localStorage.getItem(key) || '{}');
                if (parsed.access_token) {
                    const now = Math.floor(Date.now() / 1000);
                    if (parsed.expires_at && parsed.expires_at > now + 30) {
                        return parsed.access_token;
                    }
                }
            }
        }
    } catch (_) {}
    return null;
}
window.getValidAuthToken = getValidAuthToken;

async function safeSupabaseRest(endpoint, options = {}) {
    const method = (options.method || 'GET').toUpperCase();
    const url = endpoint.startsWith('http') 
        ? endpoint 
        : `${SUPABASE_URL}/rest/v1/${endpoint.replace(/^\/+/, '')}`;

    const token = await getValidAuthToken();
    const authHeader = token ? `Bearer ${token}` : `Bearer ${SUPABASE_ANON_KEY}`;

    let headers = {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': authHeader,
        'Content-Type': 'application/json',
        ...(options.headers || {})
    };

    const fetchOpts = {
        method: method,
        headers: headers
    };

    if (options.body) {
        fetchOpts.body = typeof options.body === 'string' ? options.body : JSON.stringify(options.body);
    }

    try {
        const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
        let timeoutId = null;
        if (controller) {
            timeoutId = setTimeout(() => controller.abort(), 12000);
            fetchOpts.signal = controller.signal;
        }

        let res = await fetch(url, fetchOpts);
        if (timeoutId) clearTimeout(timeoutId);

        if (!res.ok && (res.status === 401 || res.status === 403) && authHeader !== `Bearer ${SUPABASE_ANON_KEY}`) {
            headers['Authorization'] = `Bearer ${SUPABASE_ANON_KEY}`;
            fetchOpts.headers = headers;
            const resAnon = await fetch(url, fetchOpts);
            if (resAnon.ok) {
                const txt = await resAnon.text();
                return txt ? JSON.parse(txt) : true;
            }
        }

        if (res.ok) {
            const text = await res.text();
            return text ? JSON.parse(text) : true;
        } else {
            const errTxt = await res.text().catch(() => '');
            console.warn(`Supabase REST [${method} ${endpoint}] returned ${res.status}:`, errTxt);
            return null;
        }
    } catch (err) {
        if (method === 'GET' && authHeader !== `Bearer ${SUPABASE_ANON_KEY}`) {
            try {
                headers['Authorization'] = `Bearer ${SUPABASE_ANON_KEY}`;
                fetchOpts.headers = headers;
                delete fetchOpts.signal;
                const fallbackRes = await fetch(url, fetchOpts);
                if (fallbackRes.ok) {
                    const txt = await fallbackRes.text();
                    return txt ? JSON.parse(txt) : true;
                }
            } catch (_) {}
        }
        console.warn(`Supabase REST connection notice on ${endpoint}:`, err.message || err);
        return null;
    }
}

window.safeSupabaseRest = safeSupabaseRest;
window.fetchSupabaseRest = safeSupabaseRest;
