(() => {
  const API = "/api";
  const API_PUBLIC = "https://api.det-app.ru";
  const PKG = "ru.detapp.app";

  const year = document.querySelector("[data-year]");
  if (year) year.textContent = String(new Date().getFullYear());

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const topbar = document.getElementById("topbar");
  const navToggle = document.getElementById("nav-toggle");
  const siteNav = document.getElementById("site-nav");
  const onScroll = () => {
    if (!topbar) return;
    topbar.classList.toggle("is-solid", window.scrollY > 24);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  if (navToggle && topbar && siteNav) {
    navToggle.addEventListener("click", () => {
      const open = !topbar.classList.contains("is-open");
      topbar.classList.toggle("is-open", open);
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    siteNav.querySelectorAll("a").forEach((a) => {
      a.addEventListener("click", () => {
        topbar.classList.remove("is-open");
        navToggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  const nodes = document.querySelectorAll(".reveal");
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
      const heroBuild = document.getElementById("hero-build");
      if (heroBuild) heroBuild.textContent = ver;
      if (notes && m.notes) {
        notes.hidden = false;
        notes.textContent = String(m.notes);
      }
      if (win && (m.windows_setup_url || m.url)) {
        const setupUrl = m.windows_setup_url || m.url;
        const setupSize = m.windows_setup_url
          ? m.windows_setup_size
          : m.size;
        win.href = setupUrl;
        const name = win.querySelector(".dl-card__name");
        if (name) {
          name.textContent = formatBytes(setupSize)
            ? `Setup · ${formatBytes(setupSize)}`
            : "Setup";
        } else {
          win.textContent = formatBytes(setupSize)
            ? `Windows Setup · ${formatBytes(setupSize)}`
            : m.windows_setup_url
              ? "Windows Setup"
              : "Windows";
        }
        setDisabled(win, false);
      }
      const winZip = document.getElementById("dl-windows-zip");
      if (winZip && m.url && m.windows_setup_url) {
        winZip.hidden = false;
        winZip.href = m.url;
        winZip.textContent = formatBytes(m.size)
          ? `Windows zip · ${formatBytes(m.size)}`
          : "Windows zip";
        setDisabled(winZip, false);
      } else if (winZip) {
        winZip.hidden = true;
      }
      const apkUrl = m.android_url || `${API_PUBLIC}/updates/android`;
      if (apk) {
        apk.href = apkUrl;
        const name = apk.querySelector(".dl-card__name");
        if (name) {
          name.textContent = formatBytes(m.android_size)
            ? `APK · ${formatBytes(m.android_size)}`
            : "APK";
        } else {
          apk.textContent = formatBytes(m.android_size)
            ? `Android APK · ${formatBytes(m.android_size)}`
            : "Android APK";
        }
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
    return `/join.html?slug=${encodeURIComponent(slug)}`;
  }

  function bookPage(slug) {
    return `/book.html?slug=${encodeURIComponent(slug)}`;
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

    const demoBtn = document.getElementById("invite-demo");
    const copyBtn = document.getElementById("invite-copy");
    const bookBtn = document.getElementById("invite-book");
    demoBtn?.addEventListener("click", () => {
      input.value = "demo";
      form.requestSubmit();
    });
    copyBtn?.addEventListener("click", async () => {
      try {
        await copyText(input.value.trim());
        markCopied(copyBtn);
      } catch {
        copyBtn.textContent = "Не скопировалось";
      }
    });

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
        if (bookBtn) {
          bookBtn.hidden = true;
          try {
            const br = await fetch(`${API}/book/${encodeURIComponent(data.slug)}/api`, {
              cache: "no-store",
            });
            if (br.ok) {
              bookBtn.href = bookPage(data.slug);
              bookBtn.hidden = false;
            }
          } catch {
            /* no public booking */
          }
        }
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
          <a class="btn btn--primary" href="${m.windows_setup_url || m.url || "#"}">${m.windows_setup_url ? "Windows Setup" : "Windows"}</a>
          <a class="btn btn--ghost" href="${m.android_url || API_PUBLIC + "/updates/android"}">Android APK</a>
        </div>`;
    } catch {
      box.textContent = "Не удалось загрузить changelog.";
    }
  }

  const SCREENS = {
    board: {
      src: "assets/ui-board.jpg",
      phone: "assets/ui-phone.jpg",
      alt: "Доска заказов Det App",
    },
    calendar: {
      src: "assets/ui-calendar.jpg",
      phone: "assets/ui-phone-calendar.jpg",
      alt: "Календарь Det App",
    },
    order: {
      src: "assets/screen-orders.jpg",
      phone: "assets/ui-order.jpg",
      alt: "Новый заказ Det App",
    },
    cash: {
      src: "assets/ui-cash.jpg",
      phone: "assets/ui-phone-cash.jpg",
      alt: "Касса Det App",
    },
  };
  let heroMode = "pc";

  function copyText(value) {
    const text = String(value || "");
    if (!text) return Promise.reject(new Error("empty"));
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise((resolve, reject) => {
      const el = document.createElement("textarea");
      el.value = text;
      el.setAttribute("readonly", "");
      el.style.position = "fixed";
      el.style.left = "-9999px";
      document.body.appendChild(el);
      el.select();
      try {
        document.execCommand("copy") ? resolve() : reject(new Error("copy"));
      } catch (err) {
        reject(err);
      } finally {
        el.remove();
      }
    });
  }

  function markCopied(btn) {
    if (!btn) return;
    const prev = btn.textContent;
    btn.classList.add("is-ok");
    btn.textContent = "Скопировано";
    setTimeout(() => {
      btn.classList.remove("is-ok");
      btn.textContent = prev;
    }, 1400);
  }

  function screenSrc(screen) {
    return heroMode === "phone" && screen.phone ? screen.phone : screen.src;
  }

  function showScreen(id) {
    const screen = SCREENS[id];
    if (!screen) return;
    const img = document.getElementById("hero-shot");
    const win = document.getElementById("hero-window");
    const shot = document.querySelector(".hero__shot");
    const src = screenSrc(screen);
    shot?.classList.toggle("is-phone", heroMode === "phone");
    const apply = () => {
      if (img) {
        img.src = src;
        img.alt = screen.alt;
        img.classList.remove("is-out");
      }
      if (win) {
        win.dataset.zoom = src;
        win.dataset.zoomAlt = screen.alt;
      }
    };
    if (img && !reduceMotion && img.getAttribute("src") !== src) {
      img.classList.add("is-out");
      setTimeout(apply, 180);
    } else {
      apply();
    }
    document.querySelectorAll(".hero__tab").forEach((tab) => {
      const on = tab.dataset.screen === id;
      tab.classList.toggle("is-on", on);
      tab.setAttribute("aria-selected", on ? "true" : "false");
    });
    document.querySelectorAll(".handset[data-screen]").forEach((el) => {
      el.classList.toggle("is-on", el.dataset.screen === id);
    });
    if (location.pathname === "/" || location.pathname.endsWith("index.html")) {
      const url = new URL(location.href);
      url.searchParams.set("screen", id);
      history.replaceState(null, "", url);
    }
  }

  function setupExplorer() {
    const tabs = [...document.querySelectorAll(".hero__tab")];
    if (!tabs.length) return;
    Object.values(SCREENS).forEach((s) => {
      const a = new Image();
      a.src = s.src;
      if (s.phone) {
        const b = new Image();
        b.src = s.phone;
      }
    });
    tabs.forEach((tab) => {
      tab.addEventListener("click", () => showScreen(tab.dataset.screen));
    });
    document.querySelectorAll("#hero-mode [data-mode]").forEach((btn) => {
      btn.addEventListener("click", () => {
        heroMode = btn.dataset.mode === "phone" ? "phone" : "pc";
        document.querySelectorAll("#hero-mode [data-mode]").forEach((el) => {
          el.classList.toggle("is-on", el === btn);
        });
        const current = document.querySelector(".hero__tab.is-on")?.dataset.screen || "board";
        showScreen(current);
      });
    });
    document.querySelectorAll(".feat[data-screen]").forEach((el) => {
      el.addEventListener("click", (e) => {
        if (e.target.closest("a,button")) return;
        showScreen(el.dataset.screen);
        document.querySelector(".hero")?.scrollIntoView({
          behavior: reduceMotion ? "auto" : "smooth",
        });
      });
    });
    document.addEventListener("keydown", (e) => {
      if (document.getElementById("zoom")?.open) return;
      if (e.target?.closest?.("#deck")) return;
      const tag = (e.target && e.target.tagName) || "";
      if (/INPUT|TEXTAREA|SELECT/.test(tag)) return;
      const ids = Object.keys(SCREENS);
      const current = document.querySelector(".hero__tab.is-on")?.dataset.screen;
      const i = ids.indexOf(current);
      if (i < 0) return;
      if (e.key === "ArrowRight") showScreen(ids[(i + 1) % ids.length]);
      if (e.key === "ArrowLeft") showScreen(ids[(i - 1 + ids.length) % ids.length]);
    });
    const start = new URLSearchParams(location.search).get("screen");
    showScreen(SCREENS[start] ? start : "board");
  }

  function setupZoom() {
    const dialog = document.getElementById("zoom");
    const img = document.getElementById("zoom-img");
    const cap = document.getElementById("zoom-cap");
    const closeBtn = document.getElementById("zoom-close");
    const prevBtn = document.getElementById("zoom-prev");
    const nextBtn = document.getElementById("zoom-next");
    if (!dialog || !img) return null;
    const zoomEls = [...document.querySelectorAll(".is-zoom")];
    const fromEls = () =>
      zoomEls
        .map((el) => ({ src: el.dataset.zoom, alt: el.dataset.zoomAlt || "" }))
        .filter((x) => x.src);
    let items = fromEls();
    let idx = 0;
    const paint = (i) => {
      if (!items.length) return;
      idx = (i + items.length) % items.length;
      img.src = items[idx].src;
      img.alt = items[idx].alt;
      if (cap) cap.textContent = items[idx].alt;
    };
    const openAt = (i) => {
      paint(i);
      if (typeof dialog.showModal === "function") dialog.showModal();
      else dialog.setAttribute("open", "");
    };
    const close = () => {
      if (typeof dialog.close === "function") dialog.close();
      else dialog.removeAttribute("open");
    };
    zoomEls.forEach((el) => {
      el.addEventListener("click", () => {
        items = fromEls();
        openAt(Math.max(0, items.findIndex((x) => x.src === el.dataset.zoom)));
      });
    });
    prevBtn?.addEventListener("click", () => paint(idx - 1));
    nextBtn?.addEventListener("click", () => paint(idx + 1));
    closeBtn?.addEventListener("click", close);
    dialog.addEventListener("click", (e) => {
      if (e.target === dialog) close();
    });
    document.addEventListener("keydown", (e) => {
      if (!dialog.open) return;
      if (e.key === "Escape") close();
      if (e.key === "ArrowRight") paint(idx + 1);
      if (e.key === "ArrowLeft") paint(idx - 1);
    });
    return (list, i) => {
      items = list;
      openAt(i);
    };
  }

  function setupDeck(openZoom) {
    const deck = document.getElementById("screens");
    const stage = document.getElementById("deck");
    const ring = document.getElementById("deck-ring");
    if (!deck || !stage || !ring) return;
    const cards = [...ring.querySelectorAll(".deck__card")];
    const notes = {};
    document.querySelectorAll("#deck-notes li").forEach((li) => {
      notes[li.dataset.key] = {
        title: li.querySelector("b")?.textContent || "",
        text: li.querySelector("span")?.textContent || "",
      };
    });
    const caption = document.getElementById("deck-caption");
    const countEl = document.getElementById("deck-count");
    const titleEl = document.getElementById("deck-title");
    const textEl = document.getElementById("deck-text");
    const dotsEl = document.getElementById("deck-dots");
    const modeBtns = [...document.querySelectorAll("#deck-mode [data-mode]")];
    // x — доля ширины кадра, z — px, r — градусы; индекс = расстояние от центра.
    const LAYOUT = {
      pc: { x: [0, 0.56, 0.9, 1.15], z: [0, -260, -460, -620], r: [0, 40, 50, 56], o: [1, 0.85, 0.45, 0], b: [1, 0.55, 0.38, 0.3] },
      phone: { x: [0, 0.8, 1.45, 1.95], z: [0, -200, -360, -500], r: [0, 32, 42, 50], o: [1, 0.9, 0.55, 0], b: [1, 0.6, 0.42, 0.3] },
      flat: { x: [0, 1.06, 2.12, 3.18], z: [0, 0, 0, 0], r: [0, 0, 0, 0], o: [1, 0.5, 0.25, 0], b: [1, 1, 1, 1] },
    };
    const AUTOPLAY_MS = 5500;
    let mode = "pc";
    let list = [];
    let active = 0;
    let timer = 0;
    let captionTimer = 0;
    let paused = false;
    let visible = false;
    const pad = (n) => String(n).padStart(2, "0");

    const layout = () => {
      const L = reduceMotion ? LAYOUT.flat : LAYOUT[mode];
      const n = list.length;
      list.forEach((card, i) => {
        let d = i - active;
        if (d > n / 2) d -= n;
        if (d < -n / 2) d += n;
        const a = Math.min(Math.abs(d), 3);
        const s = Math.sign(d);
        card.style.transform =
          `translateX(${(-50 + s * L.x[a] * 100).toFixed(1)}%) ` +
          `translateZ(${L.z[a]}px) rotateY(${-s * L.r[a]}deg)`;
        card.style.opacity = String(L.o[a]);
        card.style.filter = a && L.b[a] < 1 ? `brightness(${L.b[a]})` : "";
        card.style.zIndex = String(10 - a);
        card.style.pointerEvents = L.o[a] > 0 ? "" : "none";
        card.classList.toggle("is-active", d === 0);
        card.setAttribute("aria-hidden", d === 0 ? "false" : "true");
      });
    };

    const paintCaption = (animate) => {
      const note = notes[list[active]?.dataset.key] || { title: "", text: "" };
      const apply = () => {
        if (countEl) countEl.textContent = `${pad(active + 1)} / ${pad(list.length)}`;
        if (titleEl) titleEl.textContent = note.title;
        if (textEl) textEl.textContent = note.text;
        caption?.classList.remove("is-out");
      };
      clearTimeout(captionTimer);
      if (!animate || reduceMotion || !caption) {
        apply();
        return;
      }
      caption.classList.add("is-out");
      captionTimer = setTimeout(apply, 200);
    };

    const paintDots = () => {
      [...dotsEl.children].forEach((b, i) => {
        b.classList.toggle("is-on", i === active);
        if (i === active) b.setAttribute("aria-current", "true");
        else b.removeAttribute("aria-current");
      });
    };

    const stop = () => {
      clearInterval(timer);
      timer = 0;
    };
    const restart = () => {
      stop();
      if (reduceMotion || paused || !visible || document.hidden) return;
      timer = setInterval(() => go(active + 1, false), AUTOPLAY_MS);
    };

    function go(i, byUser, animate = true) {
      const n = list.length;
      if (!n) return;
      active = ((i % n) + n) % n;
      layout();
      paintCaption(animate);
      paintDots();
      if (byUser) restart();
    }

    const buildDots = () => {
      dotsEl.textContent = "";
      list.forEach((card, i) => {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "deck__dot";
        b.setAttribute("aria-label", `Экран ${i + 1}: ${notes[card.dataset.key]?.title || ""}`);
        b.addEventListener("click", () => go(i, true));
        dotsEl.appendChild(b);
      });
    };

    const setMode = (m) => {
      const key = list[active]?.dataset.key;
      mode = m;
      deck.dataset.mode = m;
      list = cards.filter((c) => c.dataset.mode === m);
      cards.forEach((c) => {
        c.hidden = c.dataset.mode !== m;
        if (c.hidden) c.classList.remove("is-active");
      });
      modeBtns.forEach((b) => {
        const on = b.dataset.mode === m;
        b.classList.toggle("is-on", on);
        b.setAttribute("aria-pressed", on ? "true" : "false");
      });
      buildDots();
      const j = list.findIndex((c) => c.dataset.key === key);
      list.forEach((c) => {
        c.style.transition = "none";
      });
      go(j >= 0 ? j : 0, false, false);
      void ring.offsetWidth;
      list.forEach((c) => {
        c.style.transition = "";
      });
      restart();
    };

    const zoomActive = () => {
      if (!openZoom) return;
      const shots = list.map((c) => {
        const img = c.querySelector("img");
        return { src: img.getAttribute("src"), alt: img.alt };
      });
      openZoom(shots, active);
    };

    let x0 = null;
    let swiped = false;
    ring.addEventListener("pointerdown", (e) => {
      x0 = e.clientX;
      swiped = false;
    });
    ring.addEventListener("pointerup", (e) => {
      if (x0 === null) return;
      const dx = e.clientX - x0;
      x0 = null;
      if (Math.abs(dx) > 40) {
        swiped = true;
        go(active + (dx < 0 ? 1 : -1), true);
      }
    });
    ring.addEventListener("pointercancel", () => {
      x0 = null;
    });
    ring.addEventListener("click", (e) => {
      if (swiped) {
        swiped = false;
        return;
      }
      const i = list.indexOf(e.target.closest(".deck__card"));
      if (i < 0) return;
      if (i === active) zoomActive();
      else go(i, true);
    });

    document.getElementById("deck-prev")?.addEventListener("click", () => go(active - 1, true));
    document.getElementById("deck-next")?.addEventListener("click", () => go(active + 1, true));
    modeBtns.forEach((b) => b.addEventListener("click", () => setMode(b.dataset.mode)));

    stage.addEventListener("keydown", (e) => {
      if (e.key === "ArrowRight") {
        e.preventDefault();
        go(active + 1, true);
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        go(active - 1, true);
      } else if ((e.key === "Enter" || e.key === " ") && e.target === stage) {
        e.preventDefault();
        zoomActive();
      }
    });

    stage.addEventListener("pointerenter", (e) => {
      if (e.pointerType !== "mouse") return;
      paused = true;
      stop();
    });
    stage.addEventListener("pointerleave", (e) => {
      if (e.pointerType !== "mouse") return;
      paused = false;
      restart();
    });
    stage.addEventListener("focusin", () => {
      paused = true;
      stop();
    });
    stage.addEventListener("focusout", () => {
      paused = false;
      restart();
    });
    document.addEventListener("visibilitychange", restart);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(
        (entries) => {
          visible = entries.some((en) => en.isIntersecting);
          restart();
        },
        { threshold: 0.35 }
      ).observe(stage);
    }

    deck.classList.add("is-live");
    setMode("pc");
  }

  function setupCopies() {
    document.querySelectorAll("[data-copy]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        try {
          await copyText(btn.dataset.copy);
          markCopied(btn);
        } catch {
          btn.textContent = "Не скопировалось";
        }
      });
    });
  }

  async function setupDemo() {
    const box = document.getElementById("demo-status");
    const text = box?.querySelector(".status__text");
    const openBtn = document.getElementById("demo-open");
    const bookBtn = document.getElementById("demo-book");
    const isAndroid = /Android/i.test(navigator.userAgent);
    if (openBtn) openBtn.href = isAndroid ? intentLink("demo") : deepLink("demo");
    if (bookBtn) bookBtn.href = bookPage("demo");
    const joinBtn = document.getElementById("demo-join");
    if (joinBtn) joinBtn.href = joinPage("demo");
    if (!box || !text) return;
    try {
      const r = await fetch(`${API}/auth/studio-lookup?slug=demo`, { cache: "no-store" });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error("offline");
      box.dataset.state = "ok";
      text.textContent = `Студия «${data.name || "Demo Detailing"}» в облаке · код ${data.slug || "demo"}`;
    } catch {
      box.dataset.state = "bad";
      text.textContent = "Демо сейчас не отвечает — можно войти позже";
    }
    try {
      const b = await fetch(`${API}/book/demo/api`, { cache: "no-store" });
      if (!b.ok && bookBtn) bookBtn.hidden = true;
    } catch {
      /* branded booking page still works */
    }
  }

  function setupDock() {
    const dock = document.getElementById("dock");
    if (!dock) return;
    const onScroll = () => {
      const y = window.scrollY;
      const hideNear = document.getElementById("download");
      const near = hideNear && hideNear.getBoundingClientRect().top < window.innerHeight * 0.7;
      dock.hidden = y < 420 || !!near;
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  function formatMoney(n) {
    const num = Math.round(Number(n) || 0);
    return `${num.toLocaleString("ru-RU")} ₽`;
  }

  function animateNum(el, to, money) {
    if (!el) return;
    const target = Math.round(Number(to) || 0);
    const write = (v) => {
      el.textContent = money ? formatMoney(v) : String(v);
    };
    if (reduceMotion) {
      write(target);
      return;
    }
    const startAt = performance.now();
    const from = 0;
    const dur = 720;
    const step = (now) => {
      const p = Math.min(1, (now - startAt) / dur);
      write(Math.round(from + (target - from) * p));
      if (p < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  function paintLanes(columns) {
    const host = document.getElementById("live-lanes");
    if (!host || !Array.isArray(columns) || !columns.length) return;
    host.hidden = false;
    host.innerHTML = columns
      .map((col) => {
        const n = Math.max(0, Number(col.count) || 0);
        const ticks = Math.min(n, 12);
        const dots = Array.from({ length: ticks }, () => "<i></i>").join("");
        const name = String(col.name || "").replace(/</g, "&lt;");
        return `<button type="button" class="lane__col" data-screen="board"><span>${name}</span><b>${n}</b><div class="lane__ticks">${dots}</div></button>`;
      })
      .join("");
    if (!host.dataset.bound) {
      host.dataset.bound = "1";
      host.addEventListener("click", (e) => {
        if (!e.target.closest(".lane__col")) return;
        showScreen("board");
        document.querySelector(".hero")?.scrollIntoView({
          behavior: reduceMotion ? "auto" : "smooth",
        });
      });
    }
  }

  async function setupPulse() {
    const box = document.getElementById("pulse");
    const demoLine = document.getElementById("demo-pulse");
    const load = async (animate) => {
      const r = await fetch(`${API}/public/demo`, { cache: "no-store" });
      const data = await r.json().catch(() => ({}));
      if (!r.ok || !data.ok) throw new Error("no demo");
      const shiftLabel = document.getElementById("pulse-shift-label");
      const shiftVal = data.on_shift > 0 ? data.on_shift : data.masters_total || 0;
      if (shiftLabel) {
        shiftLabel.textContent = data.on_shift > 0 ? "на смене" : "мастеров";
      }
      if (animate) {
        animateNum(document.getElementById("pulse-open"), data.open_orders);
        animateNum(document.getElementById("pulse-shift"), shiftVal);
        animateNum(document.getElementById("pulse-done"), data.done_orders);
        animateNum(document.getElementById("pulse-pipe"), data.pipeline, true);
      } else {
        const openEl = document.getElementById("pulse-open");
        const shiftEl = document.getElementById("pulse-shift");
        const doneEl = document.getElementById("pulse-done");
        const pipeEl = document.getElementById("pulse-pipe");
        if (openEl) openEl.textContent = String(data.open_orders);
        if (shiftEl) shiftEl.textContent = String(shiftVal);
        if (doneEl) doneEl.textContent = String(data.done_orders);
        if (pipeEl) pipeEl.textContent = formatMoney(data.pipeline);
      }
      paintLanes(data.columns || []);
      if (box) box.hidden = false;
      if (demoLine) {
        demoLine.hidden = false;
        demoLine.textContent = `Сейчас в демо: ${data.open_orders} в работе · ${formatMoney(data.pipeline)} в потоке`;
      }
    };
    try {
      await load(true);
      setInterval(() => {
        load(false).catch(() => {});
      }, 45000);
    } catch {
      if (box) box.hidden = true;
    }
  }

  function setupAtlas() {
    const chips = document.getElementById("atlas-chips");
    const grid = document.getElementById("atlas-grid");
    if (!chips || !grid) return;
    const items = [...grid.querySelectorAll("figure")];
    const apply = (cat) => {
      items.forEach((fig) => {
        fig.classList.toggle("is-off", cat !== "all" && fig.dataset.cat !== cat);
      });
    };
    apply(chips.querySelector("button.is-on")?.dataset.cat || "pc");
    chips.querySelectorAll("button").forEach((btn) => {
      btn.addEventListener("click", () => {
        const cat = btn.dataset.cat;
        chips.querySelectorAll("button").forEach((el) => el.classList.toggle("is-on", el === btn));
        apply(cat);
      });
    });
  }

  function setupSmartDownload() {
    const hint = document.getElementById("dl-platform");
    const win = document.getElementById("dl-windows");
    const apk = document.getElementById("dl-android");
    const store = document.querySelector(".dl-card--store");
    const ua = navigator.userAgent || "";
    const isAndroid = /Android/i.test(ua);
    const isWin = /Windows/i.test(ua);
    if (isAndroid) {
      apk?.classList.add("is-rec");
      store?.classList.add("is-rec");
      if (hint) hint.textContent = "На этом телефоне удобнее RuStore или APK.";
    } else if (isWin) {
      win?.classList.add("is-rec");
      if (hint) hint.textContent = "На этом ПК — Windows Setup, дальше обновления из приложения.";
    } else if (hint) {
      hint.textContent = "Windows Setup, Android APK или RuStore — ниже.";
    }
  }

  function setupSpy() {
    if (!siteNav) return;
    const links = [...siteNav.querySelectorAll('a[href^="#"]')];
    const secs = links
      .map((a) => document.querySelector(a.getAttribute("href")))
      .filter(Boolean);
    if (!secs.length || !("IntersectionObserver" in window)) return;
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          const id = `#${entry.target.id}`;
          links.forEach((a) => a.classList.toggle("is-current", a.getAttribute("href") === id));
        });
      },
      { rootMargin: "-42% 0px -50% 0px", threshold: 0.01 }
    );
    secs.forEach((s) => io.observe(s));
  }

  function setupRoles() {
    document.querySelectorAll(".role[data-screen]").forEach((el) => {
      const go = () => {
        showScreen(el.dataset.screen);
        document.querySelector(".hero")?.scrollIntoView({
          behavior: reduceMotion ? "auto" : "smooth",
        });
      };
      el.addEventListener("click", go);
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          go();
        }
      });
    });
  }

  function setupFaq() {
    const items = document.querySelectorAll(".faq__list details");
    items.forEach((d) => {
      d.addEventListener("toggle", () => {
        if (!d.open) return;
        items.forEach((other) => {
          if (other !== d) other.open = false;
        });
      });
    });
  }

  function setupJoinPage() {
    const page = document.getElementById("join-page");
    if (!page) return;
    const params = new URLSearchParams(location.search);
    const slug = (params.get("slug") || params.get("invite") || "").trim().toLowerCase();
    const status = document.getElementById("join-status");
    const text = status?.querySelector(".status__text");
    const title = document.getElementById("join-title");
    const creds = document.getElementById("join-creds");
    const slugEl = document.getElementById("join-slug");
    const copyBtn = document.getElementById("join-copy");
    const openBtn = document.getElementById("join-open");
    const bookBtn = document.getElementById("join-book");
    const isAndroid = /Android/i.test(navigator.userAgent);
    if (openBtn) openBtn.href = slug ? (isAndroid ? intentLink(slug) : deepLink(slug)) : "/#invite";
    if (!slug) {
      if (status) status.dataset.state = "bad";
      if (text) text.textContent = "В ссылке нет кода студии";
      return;
    }
    if (slugEl) slugEl.textContent = slug;
    if (creds) creds.hidden = false;
    copyBtn?.addEventListener("click", async () => {
      try {
        await copyText(slug);
        markCopied(copyBtn);
      } catch {
        copyBtn.textContent = "Не скопировалось";
      }
    });
    fetch(`${API}/auth/studio-lookup?slug=${encodeURIComponent(slug)}`, { cache: "no-store" })
      .then((r) => r.json().then((data) => ({ ok: r.ok, data })))
      .then(({ ok, data }) => {
        if (!ok) throw new Error(data.detail || "Студия не найдена");
        if (status) status.dataset.state = "ok";
        if (text) text.textContent = `Студия «${data.name}» · код ${data.slug}`;
        if (title) title.textContent = data.name;
        if (bookBtn) {
          bookBtn.href = bookPage(data.slug);
          bookBtn.hidden = false;
        }
        if (isAndroid && openBtn) setTimeout(() => { location.href = openBtn.href; }, 280);
      })
      .catch((err) => {
        if (status) status.dataset.state = "bad";
        if (text) text.textContent = err.message || "Студия не найдена";
      });
  }

  function setupBookPage() {
    const form = document.getElementById("book-form");
    if (!form) return;
    const params = new URLSearchParams(location.search);
    const slug = (params.get("slug") || "demo").trim().toLowerCase();
    const status = document.getElementById("book-status");
    const text = status?.querySelector(".status__text");
    const title = document.getElementById("book-title");
    const msg = document.getElementById("book-msg");
    const submit = document.getElementById("book-submit");
    fetch(`${API}/book/${encodeURIComponent(slug)}/api`, { cache: "no-store" })
      .then((r) => r.json().then((data) => ({ ok: r.ok, data })))
      .then(({ ok, data }) => {
        if (!ok) throw new Error(data.detail || "Запись недоступна");
        if (status) status.dataset.state = "ok";
        if (text) text.textContent = `Студия «${data.company_name}» принимает заявки`;
        if (title) title.textContent = data.company_name;
        form.hidden = false;
      })
      .catch((err) => {
        if (status) status.dataset.state = "bad";
        if (text) text.textContent = err.message || "Онлайн-запись выключена";
      });
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      if (!msg || !submit) return;
      msg.classList.remove("is-error", "is-ok");
      const payload = {
        name: document.getElementById("book-name")?.value.trim() || "",
        phone: document.getElementById("book-phone")?.value.trim() || "",
        car: document.getElementById("book-car")?.value.trim() || "",
        note: document.getElementById("book-note")?.value.trim() || "",
        preferred_date: document.getElementById("book-date")?.value || "",
        preferred_time: document.getElementById("book-time")?.value || "",
      };
      if (payload.phone.length < 5) {
        msg.classList.add("is-error");
        msg.textContent = "Укажите телефон";
        return;
      }
      submit.disabled = true;
      msg.textContent = "Отправляем…";
      try {
        const r = await fetch(`${API}/book/${encodeURIComponent(slug)}`, {
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
        msg.textContent = data.message || "Заявка принята. Студия свяжется с вами.";
      } catch (err) {
        msg.classList.add("is-error");
        msg.textContent = err.message || "Ошибка отправки";
      } finally {
        submit.disabled = false;
      }
    });
  }

  loadCloudStatus();
  loadRelease().then((m) => {
    const copyApk = document.getElementById("dl-copy-apk");
    const apkUrl = m?.android_url || `${API_PUBLIC}/updates/android`;
    if (!copyApk) return;
    copyApk.hidden = false;
    copyApk.addEventListener("click", async () => {
      try {
        await copyText(apkUrl);
        markCopied(copyApk);
      } catch {
        copyApk.textContent = "Не скопировалось";
      }
    });
  });
  setupInvite();
  setupLead();
  fillChangelogPage();
  setupExplorer();
  setupDeck(setupZoom());
  setupCopies();
  setupDemo();
  setupDock();
  setupSmartDownload();
  setupSpy();
  setupRoles();
  setupFaq();
  setupJoinPage();
  setupBookPage();
  setupPulse();
  setupAtlas();
})();
