// hud.js

(function () {
    'use strict';

    var styleEl = document.createElement('style');
    styleEl.textContent = `
        @import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&display=swap');

        #pv-hud {
            position: fixed;
            top: 24px;
            right: 24px;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 6px;
            pointer-events: none;
            user-select: none;
            will-change: transform, opacity;
        }

        #pv-hud.pv-visible {
            animation: pv-slide-in 0.42s cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
        }

        #pv-hud.pv-leaving {
            animation: pv-slide-out 0.28s cubic-bezier(0.65, 0, 0.9, 0.6) forwards;
        }

        @keyframes pv-slide-in {
            from { transform: translateX(calc(100% + 48px)); opacity: 0.4; }
            to   { transform: translateX(0);                 opacity: 1;   }
        }

        @keyframes pv-slide-out {
            from { transform: translateX(0);                 opacity: 1;   }
            to   { transform: translateX(calc(100% + 48px)); opacity: 0;   }
        }

        .pv-lock {
            width: 44px;
            height: 44px;
            color: var(--pv-accent);
            filter:
                drop-shadow(0 0 2px var(--pv-accent))
                drop-shadow(0 0 8px var(--pv-glow));
        }

        .pv-label {
            font-family: 'Share Tech Mono', 'Courier New', monospace;
            font-size: 11px;
            letter-spacing: 0.2em;
            text-transform: uppercase;
            color: var(--pv-accent);
            text-shadow: 0 0 8px var(--pv-glow);
            line-height: 1;
        }
    `;
    document.head.appendChild(styleEl);

    var SVG_COMMON_ATTRS = 'class="pv-lock" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"';
    var SVG_BODY_COMMON  =
        '<rect x="4" y="11" width="16" height="12" rx="2" fill="currentColor"/>' +
        '<rect x="10.5" y="14.5" width="3" height="4" rx="1.5" fill="rgba(0,0,0,0.4)"/>';
    var PATH_ATTRS = 'stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"';

    var LOCK_CLOSED =
        '<svg ' + SVG_COMMON_ATTRS + '>' +
            SVG_BODY_COMMON +
            '<path d="M7.5 11V8.5a4.5 4.5 0 0 1 9 0V11" ' + PATH_ATTRS + '/>' +
        '</svg>';

    var LOCK_OPEN =
        '<svg ' + SVG_COMMON_ATTRS + '>' +
            SVG_BODY_COMMON +
            '<path d="M7.5 11V8.5a4.5 4.5 0 0 1 9 0V5.5" ' + PATH_ATTRS + '/>' +
        '</svg>';

    var hideTimer = null;
    var state     = 'hidden';
    var hud       = null;

    function buildHud(locked) {
        var accent = locked ? '#e03535'              : '#2ecc71';
        var glow   = locked ? 'rgba(224,53,53,0.4)'  : 'rgba(46,204,113,0.4)';
        var el     = document.createElement('div');
        el.id = 'pv-hud';
        el.style.setProperty('--pv-accent', accent);
        el.style.setProperty('--pv-glow',   glow);
        el.innerHTML =
            (locked ? LOCK_CLOSED : LOCK_OPEN) +
            '<span class="pv-label">' + (locked ? 'LOCKED' : 'UNLOCKED') + '</span>';
        return el;
    }

    function show(locked, displayTime) {
        if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }

        if (hud && hud.parentNode === document.body) {
            document.body.removeChild(hud);
        }

        hud = buildHud(locked);
        document.body.appendChild(hud);
        void hud.offsetWidth;
        hud.classList.add('pv-visible');
        state = 'visible';

        hideTimer = setTimeout(hide, displayTime || 3000);
    }

    function hide() {
        hideTimer = null;
        if (state !== 'visible' || !hud) return;
        state = 'leaving';
        var el = hud;
        hud.classList.add('pv-leaving');
        hud.addEventListener('animationend', function () {
            if (el.parentNode === document.body) document.body.removeChild(el);
            if (hud === el) hud = null;
            state = 'hidden';
        }, { once: true });
    }

    window.PVHud = { show: show, hide: hide };

})();
