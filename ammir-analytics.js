(function () {
  "use strict";
  if (window.__ammirAnalyticsLoaded) return;
  window.__ammirAnalyticsLoaded = true;

  var ENDPOINT = "https://uutwijowzewmvvrzsaww.supabase.co/functions/v1/ammir-visitor-track";
  var CONSENT_KEY = "ammir_analytics_consent_v1";
  var VISITOR_KEY = "ammir_analytics_visitor_v1";
  var SESSION_KEY = "ammir_analytics_session_v1";
  var ORIGINS = ["https://app.ammirbuild.com", "https://ammirbuild.com", "https://www.ammirbuild.com"];
  var authListenerAttached = false;

  if (ORIGINS.indexOf(location.origin) < 0) return;

  function uuid() {
    if (window.crypto && typeof window.crypto.randomUUID === "function") return window.crypto.randomUUID();
    var bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    var h = Array.from(bytes, function (b) { return b.toString(16).padStart(2, "0"); }).join("");
    return h.slice(0,8) + "-" + h.slice(8,12) + "-" + h.slice(12,16) + "-" + h.slice(16,20) + "-" + h.slice(20);
  }

  function getIds() {
    var visitor = localStorage.getItem(VISITOR_KEY);
    if (!visitor) { visitor = uuid(); localStorage.setItem(VISITOR_KEY, visitor); }
    var session = sessionStorage.getItem(SESSION_KEY);
    if (!session) { session = uuid(); sessionStorage.setItem(SESSION_KEY, session); }
    return { visitor: visitor, session: session };
  }

  function referrerHost() {
    try {
      if (!document.referrer) return null;
      var host = new URL(document.referrer).hostname;
      return host && host !== location.hostname ? host : null;
    } catch (_) { return null; }
  }

  async function sendEvent(name) {
    if (localStorage.getItem(CONSENT_KEY) !== "yes") return;
    var ids = getIds();
    var headers = { "content-type": "application/json" };
    var db = window.ammarSupabase;
    if (db && db.auth && typeof db.auth.getSession === "function") {
      try {
        var result = await db.auth.getSession();
        var token = result && result.data && result.data.session && result.data.session.access_token;
        if (token) headers.authorization = "Bearer " + token;
      } catch (_) {}
    }
    var payload = {
      event_key: uuid(),
      visitor_id: ids.visitor,
      session_id: ids.session,
      site: location.hostname === "app.ammirbuild.com" ? "app" : "website",
      event_name: name,
      page_path: (location.pathname || "/").slice(0, 512),
      page_title: (document.title || "").slice(0, 160),
      referrer_domain: referrerHost()
    };
    try {
      await fetch(ENDPOINT, {
        method: "POST",
        mode: "cors",
        credentials: "omit",
        headers: headers,
        body: JSON.stringify(payload),
        keepalive: true
      });
    } catch (_) {}
  }

  function attachAuthEvents() {
    if (authListenerAttached || location.hostname !== "app.ammirbuild.com") return;
    var attempts = 0;
    var timer = setInterval(function () {
      attempts++;
      var db = window.ammarSupabase;
      if (db && db.auth && typeof db.auth.onAuthStateChange === "function") {
        clearInterval(timer);
        authListenerAttached = true;
        db.auth.onAuthStateChange(function (event, session) {
          if (localStorage.getItem(CONSENT_KEY) === "yes" && event === "SIGNED_IN" && session && session.user) {
            sendEvent("login_success");
          }
        });
      } else if (attempts > 120) clearInterval(timer);
    }, 500);
  }

  function addAnalyticsLink() {
    var adminTab = document.getElementById("ecoAdminTab");
    if (!adminTab || adminTab.hidden || document.querySelector("[data-ammir-analytics-link]")) return;
    var link = document.createElement("a");
    link.href = "/admin-analytics.html";
    link.className = "eco-tab";
    link.setAttribute("data-ammir-analytics-link", "true");
    link.textContent = "تحليلات الزوار";
    link.style.textDecoration = "none";
    adminTab.insertAdjacentElement("afterend", link);
  }

  function addPrivacyButton() {
    if (document.getElementById("ammirPrivacySettings")) return;
    var button = document.createElement("button");
    button.id = "ammirPrivacySettings";
    button.type = "button";
    button.textContent = "إعدادات الخصوصية";
    button.style.cssText = "position:fixed;z-index:99998;bottom:12px;right:12px;border:1px solid #a9c0b5;border-radius:20px;background:#fff;color:#174c3e;padding:7px 12px;font:12px Arial,sans-serif;box-shadow:0 3px 12px #0002";
    button.addEventListener("click", function () { showConsent(true); });
    document.body.appendChild(button);
  }

  function showConsent(force) {
    if (!force && localStorage.getItem(CONSENT_KEY) !== null) return;
    if (document.getElementById("ammirAnalyticsConsent")) return;
    var box = document.createElement("section");
    box.id = "ammirAnalyticsConsent";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-label", "إعدادات الخصوصية والتحليلات");
    box.style.cssText = "position:fixed;z-index:99999;bottom:58px;left:14px;right:14px;max-width:620px;margin:auto;background:#102f29;color:#fff;padding:16px 18px;border-radius:16px;box-shadow:0 12px 38px #0003;font:14px/1.75 Arial,sans-serif;direction:rtl";
    var text = document.createElement("p");
    text.textContent = "هل تسمح لعَمِّر بقياس الزيارات لتحسين الموقع والتطبيق؟ نجمع مسار الصفحة ومصدر الزيارة ونوع الجهاز ومعرّفاً عشوائياً. عند تسجيل الدخول قد نربط الزيارة بحسابك. لا نجمع عنوان IP أو موقعك الدقيق. يمكنك تغيير اختيارك لاحقاً من إعدادات الخصوصية.";
    text.style.margin = "0 0 12px";
    var actions = document.createElement("div");
    actions.style.cssText = "display:flex;gap:8px;flex-wrap:wrap";
    function choice(value) {
      var previous = localStorage.getItem(CONSENT_KEY);
      localStorage.setItem(CONSENT_KEY, value);
      box.remove();
      if (value === "yes") {
        getIds();
        if (previous !== "yes") sendEvent("page_view");
        attachAuthEvents();
      } else {
        localStorage.removeItem(VISITOR_KEY);
        sessionStorage.removeItem(SESSION_KEY);
      }
    }
    var accept = document.createElement("button");
    accept.type = "button"; accept.textContent = "أوافق على التحليلات";
    accept.style.cssText = "border:0;border-radius:9px;background:#d69a58;color:#102f29;font-weight:700;padding:10px 14px";
    accept.addEventListener("click", function () { choice("yes"); });
    var reject = document.createElement("button");
    reject.type = "button"; reject.textContent = "لا أوافق";
    reject.style.cssText = "border:1px solid #9bb6a9;border-radius:9px;background:transparent;color:#fff;padding:10px 14px";
    reject.addEventListener("click", function () { choice("no"); });
    actions.appendChild(accept); actions.appendChild(reject);
    box.appendChild(text); box.appendChild(actions);
    document.body.appendChild(box);
  }

  function start() {
    addPrivacyButton();
    var choice = localStorage.getItem(CONSENT_KEY);
    if (choice === "yes") {
      sendEvent("page_view");
      attachAuthEvents();
    } else if (choice === null) showConsent(false);
    var observer = new MutationObserver(addAnalyticsLink);
    observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["hidden"] });
    addAnalyticsLink();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
})();