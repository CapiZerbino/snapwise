// Landing page interactions: scroll reveal, card glow, hero video tilt and the window snapping demo.
// The page is fully readable without this script.
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

// Reveal sections as they scroll into view.
const observer = new IntersectionObserver(entries => entries.forEach(entry => {
  if (!entry.isIntersecting) return;
  entry.target.classList.add('in');
  observer.unobserve(entry.target);
}), { threshold: 0.12 });
document.querySelectorAll('.reveal').forEach(el => observer.observe(el));

// Glow that follows the pointer across a card.
document.querySelectorAll('.card').forEach(card => card.addEventListener('pointermove', event => {
  const rect = card.getBoundingClientRect();
  card.style.setProperty('--mx', `${event.clientX - rect.left}px`);
  card.style.setProperty('--my', `${event.clientY - rect.top}px`);
}));

// The hero video starts tilted back and straightens as the page scrolls.
const frame = document.querySelector('.frame');
if (frame && !reduced) {
  const tilt = () => frame.style.setProperty('--tilt', `${Math.max(0, 14 - scrollY / 22)}deg`);
  addEventListener('scroll', tilt, { passive: true });
  tilt();
}
const video = document.querySelector('.frame video');
video?.addEventListener('click', () => video.paused ? video.play() : video.pause());

// Snapping demo: each button carries the target as unit fractions of the screen (x, y, width, height).
const demo = document.querySelector('.snap');
if (demo) {
  const win = demo.querySelector('.window'), ghost = demo.querySelector('.ghost'), keys = demo.querySelector('.keys');
  const buttons = [...demo.querySelectorAll('.layouts button')];
  const GAP = 1.2; // percent, the space left between a window and its neighbours
  const place = (el, [x, y, w, h]) => Object.assign(el.style, {
    left: `${x * 100 + GAP}%`, top: `${y * 100 + GAP}%`, width: `${w * 100 - GAP * 2}%`, height: `${h * 100 - GAP * 2}%`,
  });
  const rectOf = button => button.dataset.rect.split(',').map(Number);

  for (const button of buttons) {
    const [x, y, w, h] = rectOf(button);
    const glyph = document.createElement('span');
    glyph.className = 'glyph';
    glyph.innerHTML = `<b style="left:${x * 100}%;top:${y * 100}%;width:${w * 100}%;height:${h * 100}%"></b>`;
    button.prepend(glyph);
  }

  let current = 0, timer = null;
  const select = index => {
    current = index;
    const button = buttons[index];
    buttons.forEach(b => b.classList.toggle('on', b === button));
    // Show the drop preview first, then let the window follow, like a real edge drag.
    place(ghost, rectOf(button));
    ghost.style.opacity = 1;
    setTimeout(() => { place(win, rectOf(button)); ghost.style.opacity = 0; }, reduced ? 0 : 160);
    keys.innerHTML = button.dataset.keys.split(' ').map(k => `<kbd>${k}</kbd>`).join('');
  };
  const stop = () => { clearInterval(timer); timer = null; };
  buttons.forEach((button, index) => button.addEventListener('click', () => { stop(); select(index); }));
  demo.querySelector('.layouts').addEventListener('pointerenter', stop);

  place(win, rectOf(buttons[0]));
  select(0);
  // Cycle through the layouts until the visitor takes over.
  if (!reduced) timer = setInterval(() => select((current + 1) % buttons.length), 1900);
}
