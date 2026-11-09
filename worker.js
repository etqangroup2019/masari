// وسيط مساري — Cloudflare Worker
// ينشئ رابطًا مثل: https://اسمك.workers.dev/?url=<رابط الصفحة أو الملف>
// ويجلبه نيابةً عن التطبيق ويضيف ترويسات CORS. (لا يتجاوز المواقع المحمية بكابتشا أو تسجيل دخول)

// ضع هنا نطاق تطبيقك (مثل https://name.github.io) ليعمل الوسيط معه فقط.
// اتركه فارغًا للسماح للجميع (غير مستحسن لأنه يصبح وسيطًا مفتوحًا).
const ALLOW = '';

export default {
  async fetch(req) {
    const origin = req.headers.get('Origin') || '';
    const cors = {
      'Access-Control-Allow-Origin': ALLOW || '*',
      'Access-Control-Expose-Headers': 'x-final-url,content-type,content-length',
    };
    if (req.method === 'OPTIONS')
      return new Response(null, { headers: { ...cors, 'Access-Control-Allow-Methods': 'GET', 'Access-Control-Allow-Headers': '*' } });
    if (ALLOW && origin !== ALLOW) return new Response('forbidden', { status: 403, headers: cors });

    const target = new URL(req.url).searchParams.get('url');
    if (!/^https?:\/\//i.test(target || '')) return new Response('missing url', { status: 400, headers: cors });
    try {
      const r = await fetch(target, {
        redirect: 'follow',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
          'Accept': 'text/html,application/pdf,*/*;q=0.8',
          'Accept-Language': 'ar,en;q=0.8',
        },
      });
      const h = new Headers(r.headers);
      h.delete('content-security-policy');
      h.delete('set-cookie');
      for (const [k, v] of Object.entries(cors)) h.set(k, v);
      h.set('x-final-url', r.url);
      return new Response(r.body, { status: r.status, headers: h });
    } catch (e) {
      return new Response('fetch failed', { status: 502, headers: cors });
    }
  },
};
