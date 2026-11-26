(() => {
  const root = document.documentElement;
  root.classList.add('js');
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- i18n: Spanish lives in the HTML, English here ---------- */
  const EN = {
    'skip': 'Skip to content',
    'nav.features': 'Features',
    'nav.tour': 'Tour',
    'nav.engine': 'How it works',
    'nav.install': 'Install',
    'cta.download': 'Download for Mac',
    'cta.github': 'View on GitHub',
    'hero.title': 'Your PC games,<br><span class="accent">on your Mac.</span>',
    'hero.sub': 'A native app for Apple Silicon Macs. Open your Steam library, press Play and you are in. No virtual machines.',
    'facts.free': 'Free and open source',
    'facts.silicon': 'Apple Silicon, M1 or later',
    'facts.macos': 'macOS 14 Sonoma or later',
    'facts.lang': 'In English and Spanish',
    'feat.title': 'Built for playing,<br>not for configuring.',
    'feat.lib.t': 'Your Steam library, done properly',
    'feat.lib.p': 'Covers, hero art, descriptions and screenshots. Playtime, last played and which game is running right now.',
    'feat.exe.t': 'Games from outside Steam too',
    'feat.exe.p': 'Drop in an <code>.exe</code>, use <em>Open With → Cider</em> or run an installer and Cider finds the game it installed.',
    'feat.fix.t': 'Per-game fixes, automatically',
    'feat.fix.p': 'Native DLLs where games need them, windowed launch for Unity, Unreal and Source, and anti-cheat-free mode when a game offers it.',
    'feat.win.t': 'Real macOS windows',
    'feat.win.p': 'Minimize, resize or go full screen with the green button. Even in games that only offer a fixed-size window.',
    'feat.scale.t': 'More FPS on 4K and 5K displays',
    'feat.scale.p': 'Render at 75, 67 or 50 % and let macOS upscale. It makes a big difference on large displays.',
    'feat.upd.t': 'Updates itself',
    'feat.upd.p': 'When it opens it checks GitHub for new versions, downloads the update, verifies it and relaunches.',
    'tour.title': 'It sets everything up for you.',
    'tour.1.t': 'Welcome',
    'tour.1.p': 'Cider tells you what it will do before touching anything. All you need is a connection and about 2 GB free.',
    'tour.2.t': 'Setup',
    'tour.2.p': 'Checks your Mac, installs Rosetta 2 if needed, prepares the engine and downloads the official Steam client from Valve. Steam is optional.',
    'tour.3.t': 'Steam',
    'tour.3.p': 'Store, library and downloads one click away. Anything you install in Steam shows up in your Cider library on its own.',
    'tour.4.t': 'Settings',
    'tour.4.p': 'Few and clear: window style, hide Cider while playing, show FPS and Steam language.',
    'tested.title': 'Tested with real games.',
    'tested.p': 'Halo Wars: Definitive Edition and Halo: The Master Chief Collection work end to end, in anti-cheat disabled mode.',
    'engine.title': 'What happens when you press Play.',
    'engine.p': 'Cider bundles a tuned Wine runtime and DXMT, which translates Direct3D 10 and 11 to Metal. All free software, all on your Mac.',
    'pipe.1.t': 'Windows game',
    'pipe.1.p': 'The same old .exe, with DirectX 11',
    'pipe.2.p': 'Runs the game, with a patched winemac',
    'pipe.3.p': 'Direct3D 10/11 translated to Metal',
    'pipe.4.p': 'Your Apple chip GPU, at full speed',
    'compat.ok': 'Works',
    'compat.ok.1': 'to Metal via DXMT (64-bit)',
    'compat.ok.2': 'to OpenGL via wined3d',
    'compat.ok.3': 'to Metal via MoltenVK',
    'compat.no': 'Not yet',
    'compat.no.1t': 'Kernel-level anti-cheat',
    'compat.no.1': 'EasyAntiCheat or BattlEye in kernel mode, Vanguard',
    'compat.no.2t': 'Intel Macs',
    'install.title': 'Install it in a couple of minutes.',
    'step.1.t': 'Download',
    'step.1.p': 'Get the <code>.dmg</code> from the latest release.',
    'step.2.t': 'Drag',
    'step.2.p': 'Open the disk image and drag Cider to Applications.',
    'step.3.t': 'Allow',
    'step.3.p': 'Cider is not notarized by Apple yet. Open it once, then go to <em>System Settings → Privacy &amp; Security → Open Anyway</em>.',
    'step.4.t': 'Play',
    'step.4.p': 'Follow the assistant. From then on, Cider updates itself.',
    'req.1': 'Mac with Apple Silicon (M1 or later)',
    'req.2': 'macOS 14 Sonoma or later',
    'req.3': 'About 2 GB free, plus your games',
    'install.changelog': 'What is new in each version',
    'faq.title': 'Questions',
    'faq.1.q': 'How much does it cost?',
    'faq.1.a': 'Nothing. Cider is free software under the MIT License. The bundled engine keeps its own open licenses (Wine LGPL, DXMT MIT, MoltenVK and LLVM Apache 2.0).',
    'faq.2.q': 'Do I need Steam?',
    'faq.2.a': 'No. During setup you can choose “Not now, continue without Steam” and only use games you add yourself. You can install Steam later from its section. Cider never bundles Steam: it downloads the official installer from Valve.',
    'faq.3.q': 'Why does macOS block it the first time?',
    'faq.3.a': 'Because it is not notarized by Apple yet. Open it once, go to System Settings → Privacy &amp; Security and click “Open Anyway”. You only have to do this once.',
    'faq.4.q': 'Where does Cider keep its data?',
    'faq.4.a': 'In <code>~/Library/Application Support/Cider/</code>. That is where the Wine prefix, Steam and your games live. From Settings you can open the folder or reset everything.',
    'faq.5.q': 'I tried a game. How do I report it?',
    'faq.5.a': 'Open a <a href="https://github.com/alexlahoz/cider/issues/new?template=game_report.yml">game report</a> on GitHub, whether it works or not. If something breaks in the app itself, use the <a href="https://github.com/alexlahoz/cider/issues/new?template=bug_report.yml">bug report</a>.',
    'footer.made': 'Made with SwiftUI. Open source under the MIT License.',
    'footer.project': 'Project',
    'footer.releases': 'Releases',
    'footer.contrib': 'Contributing',
    'footer.licenses': 'Licenses',
    'footer.thanks': 'Thanks to',
    'footer.legal': 'Steam is a trademark of Valve Corporation. Windows, DirectX and Halo are trademarks of Microsoft. Cider is an independent project and is not affiliated with Valve, Microsoft or Apple.',
    'alt.library': 'The Cider library with Halo Wars featured, stats and your game covers',
    'alt.game': 'A game page in Cider with artwork, description and the Play button',
    'alt.window': 'Halo Wars in a macOS window: windowed, resized and in full screen',
    'alt.scale': 'Halo Wars at two render resolutions with the Metal performance HUD',
    'alt.welcome': 'Cider welcome screen',
    'alt.setup': 'Cider setup installing Steam',
    'alt.steam': 'Steam section in Cider',
    'alt.settings': 'Cider settings',
  };
  const ES_ALT = {
    'alt.welcome': 'Pantalla de bienvenida de Cider',
    'alt.setup': 'Preparación de Cider instalando Steam',
    'alt.steam': 'Sección de Steam en Cider',
    'alt.settings': 'Ajustes de Cider',
  };
  const META = {
    es: { title: document.title, desc: document.querySelector('meta[name="description"]').content },
    en: {
      title: 'Cider · PC games on your Apple Silicon Mac',
      desc: 'Cider is a native app for Apple Silicon Macs that opens your Steam library and plays your Windows games with Wine and DirectX 11 on Metal. Free and open source.',
    },
  };

  const textNodes = [...document.querySelectorAll('[data-i18n]')];
  const altNodes = [...document.querySelectorAll('[data-i18n-alt]')];
  textNodes.forEach((el) => { el.dataset.es = el.innerHTML; });
  altNodes.forEach((el) => { el.dataset.esAlt = el.alt; });

  let lang = 'es';
  function setLang(next, persist) {
    lang = next;
    root.lang = next;
    root.dataset.lang = next;
    textNodes.forEach((el) => {
      const key = el.dataset.i18n;
      el.innerHTML = next === 'en' && EN[key] ? EN[key] : el.dataset.es;
    });
    altNodes.forEach((el) => {
      const key = el.dataset.i18nAlt;
      el.alt = next === 'en' ? (EN[key] || el.dataset.esAlt) : (ES_ALT[key] || el.dataset.esAlt);
    });
    document.title = META[next].title;
    document.querySelector('meta[name="description"]').content = META[next].desc;
    renderRelease();
    if (persist) { try { localStorage.setItem('cider-lang', next); } catch (_) {} }
  }

  let initial = 'es';
  try {
    const saved = localStorage.getItem('cider-lang');
    const fromUrl = new URLSearchParams(location.search).get('lang');
    if (fromUrl === 'en' || fromUrl === 'es') initial = fromUrl;
    else if (saved === 'en' || saved === 'es') initial = saved;
    else if (!/^es\b/i.test(navigator.language || 'es')) initial = 'en';
  } catch (_) {}

  document.getElementById('langToggle').addEventListener('click', () => setLang(lang === 'es' ? 'en' : 'es', true));

  /* ---------- Latest release from GitHub (falls back to baked-in values) ---------- */
  const release = { version: '1.4.2', size: 154611357, date: '2026-11-25T22:16:23Z', url: null };
  function renderRelease() {
    const locale = lang === 'es' ? 'es-ES' : 'en-GB';
    const date = new Date(release.date).toLocaleDateString(locale, { day: 'numeric', month: 'short', year: 'numeric' });
    const mb = Math.round(release.size / 1e6);
    document.querySelectorAll('.js-version').forEach((el) => { el.textContent = release.version; });
    document.querySelectorAll('.js-size').forEach((el) => { el.textContent = `${mb} MB`; });
    document.querySelectorAll('.js-date').forEach((el) => { el.textContent = date.replace('.', ''); });
    if (release.url) document.querySelectorAll('.js-download').forEach((el) => { el.href = release.url; });
  }
  fetch('https://api.github.com/repos/alexlahoz/cider/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((data) => {
      const dmg = (data.assets || []).find((a) => /\.dmg$/i.test(a.name));
      release.version = (data.tag_name || '').replace(/^v/, '') || release.version;
      release.date = data.published_at || release.date;
      if (dmg) { release.size = dmg.size; release.url = dmg.browser_download_url; }
      renderRelease();
    })
    .catch(() => { /* keep the static fallback, links still point to releases/latest */ });

  setLang(initial, false);

  /* ---------- Nav background once the page has scrolled ---------- */
  const nav = document.querySelector('.nav');
  const sentinel = document.createElement('div');
  sentinel.style.cssText = 'position:absolute;top:0;left:0;width:1px;height:24px;pointer-events:none';
  document.body.prepend(sentinel);
  new IntersectionObserver(([e]) => nav.classList.toggle('is-scrolled', !e.isIntersecting)).observe(sentinel);

  /* ---------- Reveal on scroll ---------- */
  const revealables = document.querySelectorAll('.reveal, .hero__shot');
  document.querySelectorAll('.hero .reveal').forEach((el, i) => el.style.setProperty('--rd', `${i * 0.08}s`));
  document.querySelectorAll('.bento .reveal, .steps .reveal, .faq__list .reveal, .compat .reveal').forEach((el) => {
    const idx = [...el.parentElement.children].indexOf(el);
    el.style.setProperty('--rd', `${Math.min(idx, 5) * 0.07}s`);
  });
  if (reduceMotion || !('IntersectionObserver' in window)) {
    revealables.forEach((el) => el.classList.add('in'));
  } else {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    revealables.forEach((el) => io.observe(el));
  }

  /* ---------- Bubbles (same motif as the app's setup screens) ---------- */
  const bubbles = document.querySelector('.bubbles');
  if (bubbles && !reduceMotion) {
    const count = window.innerWidth < 640 ? 12 : 22;
    let seed = 7;
    const rand = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
    for (let i = 0; i < count; i++) {
      const b = document.createElement('span');
      const size = 4 + rand() * 18;
      b.className = 'bubble';
      b.style.cssText = `left:${rand() * 100}%;width:${size}px;height:${size}px;` +
        `--d:${12 + rand() * 16}s;--delay:${-rand() * 26}s;--x:${(rand() - 0.5) * 80}px;--o:${0.35 + rand() * 0.5}`;
      bubbles.appendChild(b);
    }
    // Pause the animation when the hero is off screen
    new IntersectionObserver(([e]) => {
      bubbles.style.display = e.isIntersecting ? '' : 'none';
    }).observe(document.querySelector('.hero'));
  }

  /* ---------- Tour tabs ---------- */
  const tabs = [...document.querySelectorAll('.tour__tabs [role="tab"]')];
  const stage = document.getElementById('panel-tour');
  const img = document.getElementById('tourImg');
  tabs.forEach((t) => { const pre = new Image(); pre.src = t.dataset.shot; });
  function select(tab, focus) {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute('aria-selected', on);
      t.tabIndex = on ? 0 : -1;
    });
    stage.setAttribute('aria-labelledby', tab.id);
    if (focus) tab.focus();
    if (img.getAttribute('src') === tab.dataset.shot) return;
    const swap = () => {
      img.src = tab.dataset.shot;
      img.dataset.i18nAlt = tab.dataset.altKey;
      img.alt = lang === 'en' ? EN[tab.dataset.altKey] : ES_ALT[tab.dataset.altKey];
      requestAnimationFrame(() => img.classList.remove('is-swapping'));
    };
    if (reduceMotion) { swap(); return; }
    img.classList.add('is-swapping');
    setTimeout(swap, 220);
  }
  tabs.forEach((t, i) => {
    t.addEventListener('click', () => select(t, false));
    t.addEventListener('keydown', (e) => {
      const keys = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 };
      if (e.key in keys) { e.preventDefault(); select(tabs[(i + keys[e.key] + tabs.length) % tabs.length], true); }
      if (e.key === 'Home') { e.preventDefault(); select(tabs[0], true); }
      if (e.key === 'End') { e.preventDefault(); select(tabs[tabs.length - 1], true); }
    });
  });
})();
