(() => {
  const API = "/api";
  const API_PUBLIC = "http://api.det-app.ru";
  const PKG = "com.example.det_app";

  const year = document.querySelector("[data-year]");
  if (year) year.textContent = String(new Date().getFullYear());

  const topbar = document.getElementById("topbar");
  const onScroll = () => {
    if (!topbar) return;
    topbar.classList.toggle("is-solid", window.scrollY > 24);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  const nodes = document.querySelectorAll(
    ".showcase, .day, .screens, .roles, .panel, .faq"
  );
  nodes.forEach((el) => el.classList.add("reveal"));
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -6% 0px" }
    );
    nodes.forEach((el) => io.observe(el));
  } else {
    nodes.forEach((el) => el.classList.add("is-in"));
  }

  // Soft parallax on hero image
  const heroImg = document.querySelector(".hero__media img");
  if (heroImg && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    window.addEventListener(
      "scroll",
      () => {
        const y = Math.min(window.scrollY, 480);
        heroImg.style.transform = `scale(1.08) translate3d(0, ${y * 0.12}px, 0)`;
      },
      { passive: true }
    );
  }

  function formatBytes(n) {
    const num = Number(n);
    if (!Number.isFinite(num) || num <= 0) return "";
    if (num < 1024 * 1024) return `${Math.round(num / 1024)} КБ`;
    return `${(num / (1024 * 1024)).toFixed(1).replace(".0", "")} МБ`;
  }

  function setDisabled(el, disabled) {
    if (!el) return;
    if (disabled) el.setAttribute("aria-disabled", "true");
    else el.removeAttribute("aria-disabled");
  }

  async function loadCloudStatus() {
    const box = document.getElementById("cloud-status");
    const text = box?.querySelector(".status__text");
    if (!box || !text) return;
    try {
      const r = await fetch(`${API}/health`, { cache: "no-store" });
      const data = await r.json().catch(() => ({}));
      if (!r.ok || !data.ok) throw new Error("bad health");
      box.dataset.state = "ok";
      text.textContent = data.version
        ? `Облако доступно · API ${data.version}`
        : "Облако доступно";
    } catch {
      box.dataset.state = "bad";
      text.textContent = "Облако сейчас недоступно";
    }
  }

  function drawQr(url) {
    const box = document.getElementById("qr-box");
    const canvas = document.getElementById("apk-qr");
    if (!box || !canvas || !url) return;
    const paint = () => {
      if (typeof QRCode === "undefined") return false;
      QRCode.toCanvas(
        canvas,
        url,
        { width: 160, margin: 1, color: { dark: "#14081c", light: "#ffffff" } },
        (err) => {
          if (!err) box.hidden = false;
        }
      );
      return true;
    };
    if (!paint()) {
      let tries = 0;
      const t = setInterval(() => {
        tries += 1;
        if (paint() || tries > 20) clearInterval(t);
      }, 150);
    }
  }

  async function loadRelease() {
    const meta = document.getElementById("release-meta");
    const notes = document.getElementById("release-notes");
    const win = document.getElementById("dl-windows");
    const apk = document.getElementById("dl-android");
    const foot = document.getElementById("foot-build");
    try {
      const r = await fetch(`${API}/updates/latest.json`, { cache: "no-store" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const m = await r.json();
      const ver = `${m.version || "?"}+${m.build || "?"}`;
      if (meta) {
        meta.textContent = `Сборка ${ver}${m.db_version ? ` · схема БД ${m.db_version}` : ""}`;
      }
      if (foot) foot.textContent = ver;
      if (notes && m.notes) {
        notes.hidden = false;
        notes.textContent = String(m.notes);
      }
      if (win && m.url) {
        win.href = m.url;
        win.textContent = formatBytes(m.size)
          ? `Windows · ${formatBytes(m.size)}`
          : "Windows";
        setDisabled(win, false);
      }
      const apkUrl = m.android_url || `${API_PUBLIC}/updates/android`;
      if (apk) {
        apk.href = apkUrl;
        apk.textContent = formatBytes(m.android_size)
          ? `Android APK · ${formatBytes(m.android_size)}`
          : "Android APK";
        setDisabled(apk, false);
      }
      drawQr(apkUrl);
      return m;
    } catch {
      if (meta) meta.textContent = "Не удалось загрузить манифест обновлений";
      if (win) {
        win.href = `${API_PUBLIC}/updates/latest.json`;
        setDisabled(win, false);
      }
      if (apk) {
        apk.href = `${API_PUBLIC}/updates/android`;
        setDisabled(apk, false);
        drawQr(apk.href);
      }
      return null;
    }
  }

  function deepLink(slug) {
    return `detapp://invite?slug=${encodeURIComponent(slug)}`;
  }

  function intentLink(slug) {
    const fallback = `${API_PUBLIC}/updates/android`;
    return (
      `intent://invite?slug=${encodeURIComponent(slug)}#Intent;` +
      `scheme=detapp;package=${PKG};` +
      `S.browser_fallback_url=${encodeURIComponent(fallback)};end`
    );
  }

  function joinPage(slug) {
    return `${API_PUBLIC}/join?slug=${encodeURIComponent(slug)}`;
  }

  function setupInvite() {
    const form = document.getElementById("invite-form");
    const input = document.getElementById("studio-slug");
    const msg = document.getElementById("invite-msg");
    const found = document.getElementById("invite-found");
    const studio = document.getElementById("invite-studio");
    const openBtn = document.getElementById("invite-open");
    const pageBtn = document.getElementById("invite-page");
    const submit = document.getElementById("invite-submit");
    if (!form || !input) return;

    const params = new URLSearchParams(location.search);
    const preset = (params.get("slug") || params.get("invite") || "").trim();
    if (preset) input.value = preset;

    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const slug = input.value.trim().toLowerCase().replace(/\s+/g, "");
      input.value = slug;
      found.hidden = true;
      msg.classList.remove("is-error", "is-ok");
      msg.textContent = "";

      if (slug.length < 2) {
        msg.classList.add("is-error");
        msg.textContent = "Введите код студии (от 2 символов)";
        return;
      }

      submit.disabled = true;
      msg.textContent = "Ищем студию…";
      try {
        const r = await fetch(
          `${API}/auth/studio-lookup?slug=${encodeURIComponent(slug)}`,
          { cache: "no-store" }
        );
        const data = await r.json().catch(() => ({}));
        if (!r.ok) {
          const detail = data.detail || "Студия не найдена";
          throw new Error(typeof detail === "string" ? detail : "Студия не найдена");
        }
        studio.textContent = `Студия «${data.name}» · код ${data.slug}`;
        const isAndroid = /Android/i.test(navigator.userAgent);
        openBtn.href = isAndroid ? intentLink(data.slug) : deepLink(data.slug);
        pageBtn.href = joinPage(data.slug);
        found.hidden = false;
        msg.classList.add("is-ok");
        msg.textContent = "Готово. Откройте приложение или страницу приглашения.";
      } catch (err) {
        msg.classList.add("is-error");
        msg.textContent = err.message || "Не удалось проверить код";
      } finally {
        submit.disabled = false;
      }
    });

    if (preset.length >= 2) form.requestSubmit();
  }

  function setupLead() {
    const form = document.getElementById("lead-form");
    const msg = document.getElementById("lead-msg");
    const submit = document.getElementById("lead-submit");
    if (!form) return;

    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      msg.classList.remove("is-error", "is-ok");
      const payload = {
        name: document.getElementById("lead-name")?.value.trim() || "",
        studio: document.getElementById("lead-studio")?.value.trim() || "",
        contact: document.getElementById("lead-contact")?.value.trim() || "",
        message: document.getElementById("lead-message")?.value.trim() || "",
      };
      if (payload.contact.length < 3) {
        msg.classList.add("is-error");
        msg.textContent = "Укажите email или телефон";
        return;
      }
      submit.disabled = true;
      msg.textContent = "Отправляем…";
      try {
        const r = await fetch(`${API}/site/leads`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        const data = await r.json().catch(() => ({}));
        if (!r.ok) {
          const detail = data.detail || "Не удалось отправить";
          throw new Error(typeof detail === "string" ? detail : "Не удалось отправить");
        }
        form.reset();
        msg.classList.add("is-ok");
        msg.textContent = "Заявка принята. Мы свяжемся с вами.";
      } catch (err) {
        msg.classList.add("is-error");
        msg.textContent = err.message || "Ошибка отправки";
      } finally {
        submit.disabled = false;
      }
    });
  }

  // changelog.html helper
  async function fillChangelogPage() {
    const box = document.getElementById("changelog-body");
    if (!box) return;
    try {
      const r = await fetch(`${API}/updates/latest.json`, { cache: "no-store" });
      const m = await r.json();
      box.innerHTML = `
        <p class="release">Сборка ${m.version}+${m.build}</p>
        <p class="release-notes">${(m.notes || "Без заметок").replace(/</g, "&lt;")}</p>
        <div class="panel__actions" style="margin-top:1.5rem">
          <a class="btn btn--primary" href="${m.url || "#"}">Windows</a>
          <a class="btn btn--ghost" href="${m.android_url || API_PUBLIC + "/updates/android"}">Android APK</a>
        </div>`;
    } catch {
      box.textContent = "Не удалось загрузить changelog.";
    }
  }

  loadCloudStatus();
  loadRelease();
  setupInvite();
  setupLead();
  fillChangelogPage();
})();
