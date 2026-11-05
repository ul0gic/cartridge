(() => {
  document.documentElement.classList.add("js");
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)");

  const top = document.querySelector("[data-top]");
  const stage = document.querySelector("[data-stage]");
  const screen = document.querySelector("[data-screen]");

  const reveals = document.querySelectorAll("[data-reveal]");
  if (reduce.matches || !("IntersectionObserver" in window)) {
    reveals.forEach((el) => el.classList.add("is-in"));
  } else {
    const io = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        }
      }
    }, { rootMargin: "0px 0px -12% 0px", threshold: 0.08 });
    reveals.forEach((el) => io.observe(el));
    document.documentElement.classList.add("reveal-ready");
  }

  const links = new Map();
  document.querySelectorAll(".tabs a").forEach((a) => {
    const target = document.querySelector(a.getAttribute("href"));
    if (target) links.set(target, a);
  });
  const updateNavigation = () => {
    let active = null;
    for (const section of links.keys()) {
      if (section.getBoundingClientRect().top <= window.innerHeight * 0.4) active = section;
    }
    links.forEach((link, section) => {
      link.classList.toggle("is-current", section === active);
      if (section === active) link.setAttribute("aria-current", "location");
      else link.removeAttribute("aria-current");
    });
  };

  // Keep every screenshot readable on smaller screens without replacing the hero motion.
  const viewer = document.createElement("dialog");
  viewer.className = "image-viewer";
  viewer.setAttribute("aria-label", "Cartridge screenshot");
  viewer.innerHTML = '<div class="viewer-bar"><p>Cartridge · A closer look</p><button class="viewer-close" type="button" autofocus>Close <span aria-hidden="true">×</span></button></div><img alt="">';
  document.body.append(viewer);
  const viewerImage = viewer.querySelector("img");
  viewer.querySelector("button").addEventListener("click", () => viewer.close());
  viewer.addEventListener("click", (event) => { if (event.target === viewer) viewer.close(); });
  document.querySelectorAll(".screen").forEach((figure) => {
    const source = figure.querySelector("img");
    const button = document.createElement("button");
    button.className = "screen-zoom";
    button.type = "button";
    button.innerHTML = 'View screenshot <span aria-hidden="true">↗</span>';
    button.setAttribute("aria-label", `View screenshot: ${source.alt}`);
    button.addEventListener("click", () => {
      viewerImage.src = source.src;
      viewerImage.alt = source.alt;
      viewer.showModal();
    });
    figure.append(button);
  });

  const target = { settle: 1, rx: 0, ry: 0 };
  const current = { settle: 1, rx: 0, ry: 0 };
  let frame = 0;

  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

  const measure = () => {
    updateNavigation();
    top.classList.toggle("is-scrolled", window.scrollY > 24);
    if (!stage || reduce.matches) return;
    const vh = window.innerHeight;
    const rect = stage.getBoundingClientRect();
    target.settle = clamp(1 - (rect.top - vh * 0.12) / (vh * 0.6), 0, 1);
  };

  const render = () => {
    frame = 0;
    let moving = false;
    for (const key of ["settle", "rx", "ry"]) {
      const delta = target[key] - current[key];
      if (Math.abs(delta) > 0.001) {
        current[key] += delta * 0.12;
        moving = true;
      } else {
        current[key] = target[key];
      }
    }
    screen.style.setProperty("--settle", current.settle.toFixed(4));
    screen.style.setProperty("--rx", `${current.rx.toFixed(3)}deg`);
    screen.style.setProperty("--ry", `${current.ry.toFixed(3)}deg`);
    if (moving) frame = requestAnimationFrame(render);
  };

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(render);
  };

  const onScroll = () => {
    measure();
    if (stage && !reduce.matches) schedule();
  };

  const onPointer = (event) => {
    if (reduce.matches || !finePointer.matches) return;
    const rect = stage.getBoundingClientRect();
    if (rect.bottom < 0 || rect.top > window.innerHeight) return;
    target.rx = (event.clientY / window.innerHeight - 0.5) * -3;
    target.ry = (event.clientX / window.innerWidth - 0.5) * 5;
    schedule();
  };

  const resetPointer = () => {
    target.rx = 0;
    target.ry = 0;
    if (!reduce.matches) schedule();
  };

  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll, { passive: true });
  if (stage && screen) {
    window.addEventListener("pointermove", onPointer, { passive: true });
    document.documentElement.addEventListener("pointerleave", resetPointer);
    reduce.addEventListener("change", () => {
      if (reduce.matches) {
        reveals.forEach((el) => el.classList.add("is-in"));
        target.rx = current.rx = 0;
        target.ry = current.ry = 0;
        cancelAnimationFrame(frame);
        frame = 0;
        screen.style.removeProperty("--settle");
        screen.style.removeProperty("--rx");
        screen.style.removeProperty("--ry");
      } else {
        onScroll();
      }
    });
    measure();
    current.settle = target.settle;
    render();
  } else {
    measure();
  }
})();
