/** Enhance the static transcript without changing its layout or accessible text.
 * @param {Document} root
 */
export function initTerminalDemo(root) {
  const terminal = root.getElementById('terminal-demo');
  if (!terminal) return;
  const pause = root.getElementById('demo-pause');
  const replay = root.getElementById('demo-replay');
  const controls = terminal.querySelector('.terminal-controls');
  const steps = [...terminal.querySelectorAll('[data-demo-step]')];
  if (!pause || !replay || !controls || !steps.length) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const visuals = steps.map(step => {
    const source = root.createElement('span');
    source.className = 'demo-static';
    source.append(...step.childNodes);
    const visual = source.cloneNode(true);
    visual.className = 'demo-visual';
    visual.setAttribute('aria-hidden', 'true');
    step.append(source, visual);
    return visual;
  });
  const walker = root.createTreeWalker(visuals[0], NodeFilter.SHOW_TEXT);
  const typingNodes = [];
  while (walker.nextNode()) typingNodes.push({ node: walker.currentNode, text: walker.currentNode.textContent });
  const characterCount = typingNodes.reduce((sum, item) => sum + item.text.length, 0);
  let timer;
  let character = 0;
  let stage = 0;
  const cancel = () => clearTimeout(timer);
  const setState = state => {
    terminal.dataset.state = state;
    pause.textContent = state === 'paused' ? 'Resume demo' : 'Pause demo';
    pause.disabled = state === 'complete';
  };
  const type = () => {
    let remaining = character;
    for (const { node, text } of typingNodes) {
      node.textContent = text.slice(0, Math.max(0, remaining));
      remaining -= text.length;
    }
  };
  const finish = () => {
    cancel();
    character = characterCount;
    type();
    visuals.forEach(visual => visual.classList.add('is-revealed'));
    setState('complete');
  };
  const tick = () => {
    if (terminal.dataset.state !== 'playing') return;
    if (character < characterCount) {
      character++;
      type();
      timer = setTimeout(tick, character === characterCount ? 600 : 30);
    } else {
      stage++;
      visuals[stage].classList.add('is-revealed');
      if (stage === visuals.length - 1) finish();
      else timer = setTimeout(tick, 800);
    }
  };
  const start = () => {
    cancel();
    if (reduced.matches) return finish();
    character = 0;
    stage = 0;
    type();
    visuals.forEach((visual, index) => visual.classList.toggle('is-revealed', index === 0));
    setState('playing');
    timer = setTimeout(tick, 30);
  };
  pause.addEventListener('click', () => {
    if (terminal.dataset.state === 'playing') {
      cancel();
      setState('paused');
    } else if (terminal.dataset.state === 'paused') {
      setState('playing');
      timer = setTimeout(tick, character < characterCount ? 30 : 800);
    }
  });
  replay.addEventListener('click', start);
  reduced.addEventListener('change', event => { if (event.matches) finish(); });
  terminal.classList.add('demo-enhanced');
  controls.hidden = false;
  root.documentElement.classList.add('motion-ready');
  start();
}
