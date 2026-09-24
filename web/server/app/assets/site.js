// Age of Dragon website. Two jobs: the phone-width menu, and the content list.
//
// THE CONTENT LIST IS READ FROM THE SAME packs.json THE GAME READS, so the page cannot
// advertise a pack the game does not offer, or miss one it does. Same origin, served
// no-cache (nginx.conf), so a publish shows here the moment the manifest goes up.

(function () {
  var toggle = document.querySelector(".nav-toggle");
  var nav = document.querySelector(".nav");
  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    nav.addEventListener("click", function (e) {
      if (e.target.tagName === "A") {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      }
    });
  }

  // THE AI NOTICE. Opens on arriving at the index page and closes itself after 30 s, or on
  // Continue, Escape or a click outside it. Once per tab: a dismissed notice does not come
  // back when the visitor returns from the credits page. sessionStorage is a convenience
  // only -- if it throws (private mode, blocked storage) the notice simply shows again.
  var notice = document.getElementById("ai-notice");
  if (notice) {
    var seen = false;
    try { seen = sessionStorage.getItem("aod-ai-notice") === "1"; } catch (e) {}
    if (!seen) {
      var left = 30;
      var count = document.getElementById("ai-notice-count");
      var ok = document.getElementById("ai-notice-ok");
      var timer = null;
      var close = function () {
        if (notice.hidden) return;
        notice.hidden = true;
        clearInterval(timer);
        document.removeEventListener("keydown", onKey);
        try { sessionStorage.setItem("aod-ai-notice", "1"); } catch (e) {}
      };
      var onKey = function (e) { if (e.key === "Escape") close(); };
      notice.hidden = false;
      if (ok) { ok.addEventListener("click", close); ok.focus(); }
      notice.addEventListener("click", function (e) { if (e.target === notice) close(); });
      document.addEventListener("keydown", onKey);
      timer = setInterval(function () {
        left -= 1;
        if (count) count.textContent = String(left);
        if (left <= 0) close();
      }, 1000);
    }
  }

  var list = document.getElementById("pack-list");
  if (!list) return;

  var KIND_WORDS = { campaign: "Campaign", map: "Map", art: "Art", audio: "Audio" };

  function size(bytes) {
    if (bytes >= 1e6) return (bytes / 1048576).toFixed(0) + " MB";
    if (bytes >= 1e3) return (bytes / 1024).toFixed(0) + " KB";
    return bytes + " B";
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  fetch("/downloads/packs.json", { cache: "no-cache" })
    .then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.json();
    })
    .then(function (manifest) {
      var packs = (manifest.packs || []).slice();
      // Required first -- it is what every player gets -- then optional, each by title.
      packs.sort(function (a, b) {
        if (a.required !== b.required) return a.required ? -1 : 1;
        return String(a.title).localeCompare(String(b.title));
      });
      list.textContent = "";
      packs.forEach(function (p) {
        var card = el("article", "panel pack");
        card.appendChild(el("h3", "", p.title || p.id));
        var meta = el("div", "meta");
        meta.appendChild(el("span", "badge plain", KIND_WORDS[p.kind] || p.kind));
        meta.appendChild(el("span", p.required ? "badge" : "badge plain",
          p.required ? "Included" : "Optional"));
        meta.appendChild(el("span", "faint", "v" + p.version + " · " + size(p.size)));
        card.appendChild(meta);
        if (p.description) card.appendChild(el("p", "", p.description));
        list.appendChild(card);
      });
      var status = document.getElementById("pack-status");
      if (status) {
        status.textContent = packs.length + " packs published · read live from the game's own manifest";
      }
    })
    .catch(function () {
      list.textContent = "";
      var status = document.getElementById("pack-status");
      if (status) status.textContent = "The content list could not be loaded right now. Everything here is also listed inside the game.";
    });
})();
