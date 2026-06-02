/* global React */
// Minimal line-icon set (stroke-based, 24x24 viewBox). Shared across views.
const ICON_PATHS = {
  gauge: 'M12 13l4-4M5.5 17a9 9 0 1 1 13 0',
  bolt: 'M13 3L5 13h6l-1 8 8-10h-6l1-8z',
  refresh: 'M3.5 9a8.5 8.5 0 0 1 14.5-3l2 2M20.5 15a8.5 8.5 0 0 1-14.5 3l-2-2M19 3v4h-4M5 21v-4h4',
  clock: 'M12 7v5l3 2M12 21a9 9 0 1 1 0-18 9 9 0 0 1 0 18z',
  chart: 'M4 19V5M4 19h16M8 15l3-4 3 2 4-6',
  copy: 'M9 9V6a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-3M5 9h7a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z',
  terminal: 'M5 7l4 4-4 4M11 16h6M3 4h18a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z',
  server: 'M4 5h16v5H4zM4 14h16v5H4zM7.5 7.5h.01M7.5 16.5h.01',
  folder: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z',
  chevDown: 'M6 9l6 6 6-6',
  chevRight: 'M9 6l6 6-6 6',
  chevUp: 'M6 15l6-6 6 6',
  plus: 'M12 5v14M5 12h14',
  external: 'M14 5h5v5M19 5l-7 7M11 5H6a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5',
  seal: 'M9 12l2 2 4-4M12 3l2.3 1.7 2.8-.2 1 2.7 2.4 1.5-.9 2.7.9 2.7-2.4 1.5-1 2.7-2.8-.2L12 21l-2.3-1.7-2.8.2-1-2.7L3.5 15.3l.9-2.7-.9-2.7 2.4-1.5 1-2.7 2.8.2z',
  info: 'M12 11v5M12 7.5h.01M12 21a9 9 0 1 1 0-18 9 9 0 0 1 0 18z',
  warn: 'M12 9v4M12 16.5h.01M10.3 4l-7.5 13A1.5 1.5 0 0 0 4 19.3h16a1.5 1.5 0 0 0 1.3-2.3l-7.5-13a1.5 1.5 0 0 0-2.6 0z',
  x: 'M6 6l12 12M18 6L6 18',
  check: 'M5 12l5 5 9-11',
  settings: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM19.4 13a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2v.1a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-2.9-1.2l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0-1.2-2.9H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.2-2.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 2.9-1.2V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 2.9 1.2l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0 1.2 2.9h.1a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.6 1z',
  key: 'M15.5 7.5a3.5 3.5 0 1 1-4.9 3.2L4 17.3V20h2.7l.6-.6v-1.8h1.8l1.2-1.2v-1.8h1.6l.5-.5A3.5 3.5 0 0 1 15.5 7.5zM16.2 7.8h.01',
  bell: 'M18 8a6 6 0 1 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0',
  sliders: 'M4 6h10M18 6h2M4 12h2M10 12h10M4 18h7M15 18h5M14 4v4M6 10v4M11 16v4',
  shield: 'M12 3l8 3v6c0 5-3.5 7.5-8 9-4.5-1.5-8-4-8-9V6l8-3zM9 12l2 2 4-4',
  menubar: 'M3 5h18v14H3zM3 9h18M7 7h.01M10 7h.01',
  dollar: 'M12 3v18M16 7.5c0-1.7-1.8-2.5-4-2.5s-4 .8-4 2.5 1.8 2.4 4 2.9 4 1.2 4 3-1.8 2.6-4 2.6-4-.9-4-2.6',
  info2: 'M12 16v-5M12 8h.01',
  sun: 'M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10zM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
  moon: 'M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z',
  grip: 'M9 6h.01M9 12h.01M9 18h.01M15 6h.01M15 12h.01M15 18h.01',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4',
  stop: 'M7 7h10v10H7z',
  trash: 'M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13',
  download: 'M12 3v12M7 11l5 5 5-5M5 21h14',
  power: 'M12 3v9M6.5 7a8 8 0 1 0 11 0',
  pin: 'M9 3h6l-1 7 3 3v2h-4v4l-1 2-1-2v-4H6v-2l3-3-1-7z',
  pinOff: 'M9 3h6l-1 7M6 13v2h4M14 14l2 1v-2M12 17v4l-1 2-1-2v-4M4 4l16 16',
};

function Icon({ name, size = 16, stroke = 1.7, fill = false, style, className }) {
  const d = ICON_PATHS[name];
  return (
    <svg
      width={size} height={size} viewBox="0 0 24 24"
      fill="none" stroke="currentColor"
      strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round"
      style={style} className={className} aria-hidden="true"
    >
      <path d={d} />
    </svg>
  );
}

window.Icon = Icon;
