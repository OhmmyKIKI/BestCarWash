// supabase-client.js (owner local copy)
// Supabase Configuration
var SUPABASE_URL = 'https://mrmtbzbfmgdfjsrdnzbv.supabase.co';
var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ybXRiemJmbWdkZmpzcmRuemJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzMDE4NDcsImV4cCI6MjEwNDg3Nzg0N30.HXCGJ4byqFdEERHEOo_YaQA2DdF0-AsvRi1F54Uj0eI';

// Safe initializer to ensure supabaseClient is always available
function resilientFetch(url, options) {
    let retries = 2;
    return new Promise(function(resolve, reject) {
        function attempt() {
            fetch(url, options)
                .then(resolve)
                .catch(function(err) {
                    if (retries > 0) {
                        retries--;
                        setTimeout(attempt, 400);
                    } else {
                        reject(err);
                    }
                });
        }
        attempt();
    });
}

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
                fetch: resilientFetch
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

