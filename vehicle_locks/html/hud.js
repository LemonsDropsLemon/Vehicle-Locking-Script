// hud.js

(function () {
    'use strict';

    var styleEl = document.createElement('style');
    styleEl.textContent = `
        @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@700&display=swap');

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

        #pv-alarm-hud {
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

        /* When the lock HUD is also visible, push the alarm HUD below it */
        #pv-hud.pv-visible ~ #pv-alarm-hud,
        #pv-hud.pv-leaving ~ #pv-alarm-hud {
            top: 108px;
        }

        #pv-hud.pv-visible, #pv-alarm-hud.pv-visible {
            animation: pv-slide-in 0.42s cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
        }

        #pv-hud.pv-leaving, #pv-alarm-hud.pv-leaving {
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

        @keyframes pv-alarm-pulse {
            0%, 100% { opacity: 1;   }
            50%       { opacity: 0.5; }
        }

        #pv-alarm-hud.pv-visible .pv-lock,
        #pv-alarm-hud.pv-visible .pv-label {
            animation: pv-alarm-pulse 0.9s ease-in-out infinite;
        }

        .pv-lock {
            width: 44px;
            height: 44px;
            color: var(--pv-accent);
        }

        .pv-label {
            font-family: 'Orbitron', 'Courier New', monospace;
            font-size: 11px;
            font-weight: 700;
            letter-spacing: 0.2em;
            text-transform: uppercase;
            color: var(--pv-accent);
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

    var ALARM_BELL =
        '<svg ' + SVG_COMMON_ATTRS + '>' +
            '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>' +
            '<path d="M13.73 21a2 2 0 0 1-3.46 0" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>' +
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

    var alarmState = 'hidden';
    var alarmHud   = null;

    function buildAlarmHud() {
        var el = document.createElement('div');
        el.id = 'pv-alarm-hud';
        el.style.setProperty('--pv-accent', '#f39c12');
        el.style.setProperty('--pv-glow',   'rgba(243,156,18,0.45)');
        el.innerHTML =
            ALARM_BELL +
            '<span class="pv-label">ALARM</span>';
        return el;
    }

    function showAlarm() {
        if (alarmHud && alarmHud.parentNode === document.body) {
            document.body.removeChild(alarmHud);
        }

        alarmHud = buildAlarmHud();
        document.body.appendChild(alarmHud);
        void alarmHud.offsetWidth;
        alarmHud.classList.add('pv-visible');
        alarmState = 'visible';
    }

    function hideAlarm() {
        if (alarmState !== 'visible' || !alarmHud) return;
        alarmState = 'leaving';
        var el = alarmHud;
        alarmHud.classList.add('pv-leaving');
        alarmHud.addEventListener('animationend', function () {
            if (el.parentNode === document.body) document.body.removeChild(el);
            if (alarmHud === el) alarmHud = null;
            alarmState = 'hidden';
        }, { once: true });
    }

    window.PVHud = { show: show, hide: hide, showAlarm: showAlarm, hideAlarm: hideAlarm };

})();