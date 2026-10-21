// supabase-client.js
// Supabase Configuration & Resilient Client
var SUPABASE_DIRECT_URL = 'https://mrmtbzbfmgdfjsrdnzbv.supabase.co';
var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ybXRiemJmbWdkZmpzcmRuemJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzMDE4NDcsImV4cCI6MjEwNDg3Nzg0N30.HXCGJ4byqFdEERHEOo_YaQA2DdF0-AsvRi1F54Uj0eI';

function getPreferredSupabaseUrl() {
    try {
        if (typeof window !== 'undefined' && window.location) {
            const host = window.location.hostname;
            if (host && (host.endsWith('vercel.app') || host.includes('bestcarwash'))) {
                return window.location.origin + '/api/supabase';
            }
        }
    } catch (_) {}
    return SUPABASE_DIRECT_URL;
}

var SUPABASE_URL = getPreferredSupabaseUrl();

// Safe initializer to ensure supabaseClient is always available
function getSupabaseClient() {
    if (window.supabaseClient) return window.supabaseClient;
    if (window.supabase && typeof window.supabase.createClient === 'function') {
        window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
            auth: {
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: true
            },
            global: {
                fetch: async (url, options = {}) => {
                    const strUrl = String(url);
                    const authHeader = options.headers?.Authorization || options.headers?.authorization || '';
                    const isAuthLarge = authHeader.length > 1200;
                    const method = (options.method || 'GET').toUpperCase();

                    // Guard: For GET requests on proxy, never send bloated JWTs
                    if (strUrl.includes('/api/supabase') && (isAuthLarge || method === 'GET')) {
                        if (method === 'GET') {
                            const newHeaders = { ...options.headers, Authorization: `Bearer ${SUPABASE_ANON_KEY}` };
                            return fetch(url, { ...options, headers: newHeaders, credentials: 'omit' });
                        }
                    }

                    let res = await fetch(url, { ...options, credentials: 'omit' }).catch(() => null);
                    // If Vercel returns 494/431 (Header Too Large) or direct connection reset, failover to Serverless Proxy
                    if (!res || !res.ok && (res.status === 494 || res.status === 431)) {
                        try {
                            const cleanEndpoint = strUrl.replace(/^.*?\/rest\/v1\//, '');
                            const token = (authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '') || SUPABASE_ANON_KEY;
                            return await fetch('/api/proxy', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                credentials: 'omit',
                                body: JSON.stringify({
                                    endpoint: cleanEndpoint,
                                    method: method,
                                    token: token,
                                    body: options.body
                                })
                            });
                        } catch (_) {}
                    }
                    return res || new Response(JSON.stringify({ error: 'Connection failed' }), { status: 503 });
                }
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
window.SUPABASE_DIRECT_URL = SUPABASE_DIRECT_URL;
window.SUPABASE_URL = SUPABASE_URL;
window.SUPABASE_ANON_KEY = SUPABASE_ANON_KEY;

// Safe token resolver that checks expiration and auto-refreshes if needed
async function getValidAuthToken() {
    let token = null;
    try {
        const client = getSupabaseClient();
        if (client && client.auth) {
            const { data } = await client.auth.getSession().catch(() => ({ data: null }));
            const sess = data?.session;
            if (sess?.access_token) {
                const now = Math.floor(Date.now() / 1000);
                if (sess.expires_at && sess.expires_at > now + 30) {
                    token = sess.access_token;
                } else {
                    const refreshRes = await client.auth.refreshSession().catch(() => null);
                    if (refreshRes?.data?.session?.access_token) {
                        token = refreshRes.data.session.access_token;
                    }
                }
            }
        }
    } catch (_) {}

    if (!token) {
        try {
            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                if (key && (key.startsWith('sb-') && key.endsWith('-auth-token'))) {
                    const parsed = JSON.parse(localStorage.getItem(key) || '{}');
                    if (parsed.access_token) {
                        const now = Math.floor(Date.now() / 1000);
                        if (parsed.expires_at && parsed.expires_at > now + 30) {
                            token = parsed.access_token;
                            break;
                        }
                    }
                }
            }
        } catch (_) {}
    }

    // Critical Guard: Prevent HTTP 494 REQUEST_HEADER_TOO_LARGE on proxies
    // Normal JWT tokens are ~800 to 1,500 chars. If > 2,500 chars, it contains bloated base64 metadata.
    // We trigger automatic cleanup while still providing the token for direct Supabase requests (supports up to 32KB).
    if (token && token.length > 2500) {
        triggerUserMetadataCleanup().catch(() => {});
        return token;
    }

    return token;
}
window.getValidAuthToken = getValidAuthToken;

var isSanitizing = window._isSanitizingAuth || false;
async function triggerUserMetadataCleanup() {
    if (isSanitizing || window._isSanitizingAuth) return;
    isSanitizing = true;
    window._isSanitizingAuth = true;
    try {
        // 1. Immediately purge bloated base64 from localStorage auth cache to free quota
        try {
            for (let i = 0; i < localStorage.length; i++) {
                const k = localStorage.key(i);
                if (k && k.startsWith('sb-') && k.endsWith('-auth-token')) {
                    const raw = localStorage.getItem(k);
                    if (raw && (raw.includes('data:image') || raw.length > 10000)) {
                        const parsed = JSON.parse(raw);
                        if (parsed.user?.user_metadata) {
                            let modified = false;
                            for (const [mKey, mVal] of Object.entries(parsed.user.user_metadata)) {
                                if (typeof mVal === 'string' && (mVal.startsWith('data:') || mVal.length > 500)) {
                                    delete parsed.user.user_metadata[mKey];
                                    modified = true;
                                } else if (Array.isArray(mVal) && mVal.some(x => typeof x === 'string' && (x.startsWith('data:') || x.length > 500))) {
                                    delete parsed.user.user_metadata[mKey];
                                    modified = true;
                                }
                            }
                            if (modified) {
                                localStorage.setItem(k, JSON.stringify(parsed));
                                console.log('[Supabase] Sanitized base64 from localStorage:', k);
                            }
                        }
                    }
                }
            }
        } catch (_) {}

        const client = getSupabaseClient();
        if (!client || !client.auth) return;
        const { data } = await client.auth.getSession().catch(() => ({ data: null }));
        const user = data?.session?.user;
        if (!user || !user.user_metadata) return;

        // Clean bloated base64 keys directly from Supabase Auth
        const meta = user.user_metadata;
        const purgedMeta = {};
        let foundBloat = false;

        for (const [key, val] of Object.entries(meta)) {
            if (typeof val === 'string' && (val.startsWith('data:') || val.length > 500)) {
                foundBloat = true;
                purgedMeta[key] = null;
            } else if (Array.isArray(val) && (val.length > 20 || val.some(item => typeof item === 'string' && (item.startsWith('data:') || item.length > 500)))) {
                foundBloat = true;
                purgedMeta[key] = null;
            }
        }

        if (foundBloat) {
            console.log('[Supabase] Purging bloated metadata keys:', Object.keys(purgedMeta));
            // First attempt via Serverless Proxy (immune to HTTP 494 and ISP reset)
            try {
                const proxyPurge = await fetch('/api/proxy', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    credentials: 'omit',
                    body: JSON.stringify({ action: 'purge_metadata', token: data?.session?.access_token })
                });
                if (proxyPurge.ok) {
                    await client.auth.refreshSession().catch(() => null);
                    console.log('[Supabase] Auth metadata purged via Serverless Proxy successfully');
                    return;
                }
            } catch (_) {}

            await client.auth.updateUser({ data: purgedMeta }).catch(e => console.warn('[Supabase] updateUser cleanup notice:', e));
            await client.auth.refreshSession().catch(() => null);
            console.log('[Supabase] Auth session refreshed with clean compact token');
        }
    } catch (e) {
        // Silent catch to prevent console noise
    } finally {
        isSanitizing = false;
        window._isSanitizingAuth = false;
    }
}
window.triggerUserMetadataCleanup = triggerUserMetadataCleanup;

if (typeof window !== 'undefined') {
    setTimeout(() => {
        triggerUserMetadataCleanup().catch(() => {});
    }, 1500);
}

function formatRestResponse(parsed, error = null) {
    if (error) {
        const errObj = [];
        Object.defineProperty(errObj, 'data', { value: null, enumerable: false, configurable: true });
        Object.defineProperty(errObj, 'error', { value: error, enumerable: false, configurable: true });
        return errObj;
    }
    if (Array.isArray(parsed)) {
        Object.defineProperty(parsed, 'data', {
            get: function() { return this; },
            enumerable: false,
            configurable: true
        });
        Object.defineProperty(parsed, 'error', {
            value: null,
            enumerable: false,
            configurable: true
        });
        return parsed;
    }
    if (parsed && typeof parsed === 'object') {
        if (!('data' in parsed)) {
            Object.defineProperty(parsed, 'data', {
                get: function() { return this; },
                enumerable: false,
                configurable: true
            });
        }
        if (!('error' in parsed)) {
            Object.defineProperty(parsed, 'error', {
                value: null,
                enumerable: false,
                configurable: true
            });
        }
        return parsed;
    }
    return { ok: true, data: parsed, error: null };
}

// Resilient REST fetcher to eliminate net::ERR_CONNECTION_RESET and handle RLS gracefully
async function safeSupabaseRest(endpoint, options = {}) {
    const method = (options.method || 'GET').toUpperCase();
    const cleanEndpoint = endpoint.replace(/^\/+/, '');

    const token = await getValidAuthToken();
    const isTokenLarge = token && token.length > 1200;

    const candidateBases = [];
    if (typeof window !== 'undefined' && window.location.origin) {
        // Primary Tunnel: Serverless Proxy (Zero-494 guarantee, payload in body)
        candidateBases.push('/api/proxy');
        if (window.location.hostname.includes('vercel.app')) {
            candidateBases.push(window.location.origin + '/api/supabase');
        }
    }
    candidateBases.push(SUPABASE_URL || SUPABASE_DIRECT_URL);
    candidateBases.push(SUPABASE_DIRECT_URL);

    const defaultAuthHeader = token ? `Bearer ${token}` : `Bearer ${SUPABASE_ANON_KEY}`;
    let lastErr = null;

    for (let i = 0; i < candidateBases.length; i++) {
        const base = candidateBases[i];

        // 1. HIGH-CAPACITY SERVERLESS PROXY TUNNEL
        if (base === '/api/proxy') {
            try {
                const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
                let timeoutId = null;
                if (controller) timeoutId = setTimeout(() => controller.abort(), 12000);

                const proxyRes = await fetch('/api/proxy', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    credentials: 'omit',
                    signal: controller ? controller.signal : undefined,
                    body: JSON.stringify({
                        endpoint: cleanEndpoint,
                        method: method,
                        token: token,
                        body: options.body
                    })
                });
                if (timeoutId) clearTimeout(timeoutId);

                if (proxyRes.ok) {
                    const parsed = await proxyRes.json().catch(() => true);
                    return formatRestResponse(parsed);
                }
            } catch (proxyErr) {
                console.warn('Serverless proxy notice:', proxyErr.message || proxyErr);
            }
            continue;
        }
        const isProxy = base.includes('/api/supabase');
        const url = endpoint.startsWith('http') ? endpoint : `${base}/rest/v1/${cleanEndpoint}`;

        // Vercel / Nginx proxy rejects large headers with HTTP 494.
        // For public GET requests or large tokens on proxy, use anon key to guarantee safe header size.
        let activeAuth = defaultAuthHeader;
        if (isProxy && (method === 'GET' || isTokenLarge)) {
            activeAuth = `Bearer ${SUPABASE_ANON_KEY}`;
        }

        const reqHeaders = {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': activeAuth,
            ...(options.headers || {})
        };

        if (options.body || method === 'POST' || method === 'PUT' || method === 'PATCH') {
            reqHeaders['Content-Type'] = 'application/json';
        }

        const fetchOpts = {
            method: method,
            headers: reqHeaders,
            credentials: 'omit'
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

            // If 494/431 (Header Too Large) or 401/403 (Auth invalid), retry immediately with anon key
            if (!res.ok && (res.status === 494 || res.status === 431 || res.status === 401 || res.status === 403) && activeAuth !== `Bearer ${SUPABASE_ANON_KEY}`) {
                reqHeaders['Authorization'] = `Bearer ${SUPABASE_ANON_KEY}`;
                fetchOpts.headers = reqHeaders;
                const resAnon = await fetch(url, fetchOpts);
                if (resAnon.ok) {
                    const txt = await resAnon.text();
                    const parsed = txt ? JSON.parse(txt) : true;
                    return formatRestResponse(parsed);
                }
            }

            if (res.ok) {
                const text = await res.text();
                const parsed = text ? JSON.parse(text) : true;
                return formatRestResponse(parsed);
            } else {
                const errTxt = await res.text().catch(() => '');
                lastErr = new Error(errTxt || `HTTP ${res.status}`);
                // Don't stop loop on 494, 431, 502, 503, 504 - failover to next tunnel
                if (res.status >= 400 && res.status < 500 && res.status !== 404 && res.status !== 494 && res.status !== 431) {
                    console.warn(`Supabase REST [${method} ${cleanEndpoint}] returned ${res.status}:`, errTxt);
                    return formatRestResponse(null, lastErr);
                }
            }
        } catch (fetchErr) {
            lastErr = fetchErr;
            console.warn(`Supabase tunnel [${base}] notice on ${cleanEndpoint}:`, fetchErr.message || fetchErr);
        }

        if (endpoint.startsWith('http')) break;
    }

    return formatRestResponse(null, lastErr || new Error('Connection failed'));
}

window.safeSupabaseRest = safeSupabaseRest;
window.fetchSupabaseRest = safeSupabaseRest;
