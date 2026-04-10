// audio.js

(function () {
    'use strict';

    var ctx = new (window.AudioContext || window.webkitAudioContext)();

    function tryResume() { if (ctx.state === 'suspended') ctx.resume(); }
    window.addEventListener('focus', tryResume);
    document.addEventListener('click',   tryResume, { once: true });
    document.addEventListener('keydown', tryResume, { once: true });


    var masterFilter = ctx.createBiquadFilter();
    masterFilter.type            = 'lowpass';
    masterFilter.frequency.value = 20000;
    masterFilter.Q.value         = 0.5;
    masterFilter.connect(ctx.destination);
    var convolver = (function () {
        var duration   = 1.8;
        var sampleRate = ctx.sampleRate;
        var length     = Math.floor(sampleRate * duration);
        var ir         = ctx.createBuffer(2, length, sampleRate);
        for (var c = 0; c < 2; c++) {
            var d = ir.getChannelData(c);
            for (var i = 0; i < length; i++) {
                d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, 3);
            }
        }
        var node = ctx.createConvolver();
        node.buffer = ir;
        node.connect(masterFilter);
        return node;
    })();

    var bufferCache   = {};
    var bufferLoading = {};

    function loadBuffer(file) {
        if (bufferCache[file])   return Promise.resolve(bufferCache[file]);
        if (bufferLoading[file]) return bufferLoading[file];
        bufferLoading[file] = fetch('./sounds/' + file + '.ogg')
            .then(function (r)   { return r.arrayBuffer(); })
            .then(function (ab)  { return ctx.decodeAudioData(ab); })
            .then(function (buf) {
                bufferCache[file] = buf;
                delete bufferLoading[file];
                return buf;
            });
        return bufferLoading[file];
    }

    function computeSpatial(srcX, srcY, playerX, playerY, fwdX, fwdY, maxDist, reverbMaxWet, reverbStart) {
        var dx    = srcX - playerX;
        var dy    = srcY - playerY;
        var dist  = Math.sqrt(dx * dx + dy * dy);
        var ratio = dist >= maxDist ? 1.0 : dist / maxDist;
        var gain  = 1.0 - ratio;
        var rs  = reverbStart || 0;
        var wet = 0.0;
        if (ratio > rs) {
            var t = (ratio - rs) / (1.0 - rs);
            wet = Math.sin(t * Math.PI) * (reverbMaxWet || 0);
        }
        var rightX =  fwdY;
        var rightY = -fwdX;
        var pan = 0.0;
        if (dist > 0.01) {
            pan = (dx * rightX + dy * rightY) / dist;
            pan = pan < -1.0 ? -1.0 : pan > 1.0 ? 1.0 : pan;
        }
        return { gain: gain, pan: pan, wet: wet };
    }

    var SMOOTH_TC = 0.05;

    function buildChain(buf, loop, useReverb) {
        var source = ctx.createBufferSource();
        source.buffer = buf;
        source.loop   = !!loop;

        var dryGain = ctx.createGain();
        var panNode = ctx.createStereoPanner();
        source.connect(dryGain);
        dryGain.connect(panNode);
        panNode.connect(masterFilter);

        var wetGain = null;
        if (useReverb) {
            wetGain = ctx.createGain();
            wetGain.gain.value = 0;
            source.connect(wetGain);
            wetGain.connect(convolver);
        }

        return { source: source, gainNode: dryGain, panNode: panNode, wetGain: wetGain };
    }

    function disconnectChain(nodes) {
        try { nodes.source.stop();         } catch (e) {}
        try { nodes.source.disconnect();   } catch (e) {}
        try { nodes.gainNode.disconnect(); } catch (e) {}
        try { nodes.panNode.disconnect();  } catch (e) {}
        if (nodes.wetGain) {
            try { nodes.wetGain.disconnect(); } catch (e) {}
        }
    }

    var activeAlarms   = {};
    var activeOneShots = {};
    var oneShotId      = 0;

    function reverbParams(data) {
        return {
            useReverb:    !!data.reverbEnabled,
            reverbMaxWet: data.reverbMaxWet || 0,
            reverbStart:  data.reverbStart  || 0,
        };
    }


    function applyInitial(nodes, volume, sp) {
        nodes.gainNode.gain.value = volume * sp.gain;
        nodes.panNode.pan.value   = sp.pan;
        if (nodes.wetGain) nodes.wetGain.gain.value = volume * sp.wet;
    }

    function playSound(data) {
        tryResume();
        var rv = reverbParams(data);
        loadBuffer(data.file).then(function (buf) {
            var sp    = computeSpatial(data.srcX, data.srcY, data.playerX, data.playerY, data.fwdX, data.fwdY, data.maxDist, rv.reverbMaxWet, rv.reverbStart);
            var nodes = buildChain(buf, false, rv.useReverb);
            applyInitial(nodes, data.volume, sp);
            nodes.source.start();

            var id = ++oneShotId;
            activeOneShots[id] = {
                gainNode:     nodes.gainNode,
                panNode:      nodes.panNode,
                wetGain:      nodes.wetGain,
                maxDist:      data.maxDist,
                srcX:         data.srcX,
                srcY:         data.srcY,
                baseVolume:   data.volume,
                reverbMaxWet: rv.reverbMaxWet,
                reverbStart:  rv.reverbStart,
            };
            nodes.source.onended = function () {
                disconnectChain(nodes);
                delete activeOneShots[id];
            };
        }).catch(function (e) { console.error('[PV Audio] playSound:', e); });
    }

    function startAlarm(data) {
        if (activeAlarms[data.key]) return;
        tryResume();
        var rv = reverbParams(data);
        loadBuffer(data.file).then(function (buf) {
            if (activeAlarms[data.key]) return;
            var sp    = computeSpatial(data.srcX, data.srcY, data.playerX, data.playerY, data.fwdX, data.fwdY, data.maxDist, rv.reverbMaxWet, rv.reverbStart);
            var nodes = buildChain(buf, true, rv.useReverb);
            applyInitial(nodes, data.volume, sp);
            nodes.source.start();
            activeAlarms[data.key] = {
                source:       nodes.source,
                gainNode:     nodes.gainNode,
                panNode:      nodes.panNode,
                wetGain:      nodes.wetGain,
                baseVolume:   data.volume,
                maxDist:      data.maxDist,
                srcX:         data.srcX,
                srcY:         data.srcY,
                reverbMaxWet: rv.reverbMaxWet,
                reverbStart:  rv.reverbStart,
            };
        }).catch(function (e) { console.error('[PV Audio] startAlarm:', e); });
    }

    function stopAlarm(key) {
        var alarm = activeAlarms[key];
        if (!alarm) return;
        disconnectChain(alarm);
        delete activeAlarms[key];
    }

    function updateListener(data) {
        var now = ctx.currentTime;
        var tc  = data.muffleTransition || 0.15;

        var targetFreq = data.muffled ? (data.muffleFrequency || 600) : 20000;
        masterFilter.frequency.setTargetAtTime(targetFreq, now, tc);

        for (var key in activeAlarms) {
            var a  = activeAlarms[key];
            var sp = computeSpatial(a.srcX, a.srcY, data.playerX, data.playerY, data.fwdX, data.fwdY, a.maxDist, a.reverbMaxWet, a.reverbStart);
            a.gainNode.gain.setTargetAtTime(a.baseVolume * sp.gain, now, SMOOTH_TC);
            a.panNode.pan.setTargetAtTime(sp.pan, now, SMOOTH_TC);
            if (a.wetGain) a.wetGain.gain.setTargetAtTime(a.baseVolume * sp.wet, now, SMOOTH_TC);
        }

        for (var id in activeOneShots) {
            var s  = activeOneShots[id];
            sp = computeSpatial(s.srcX, s.srcY, data.playerX, data.playerY, data.fwdX, data.fwdY, s.maxDist, s.reverbMaxWet, s.reverbStart);
            s.gainNode.gain.setTargetAtTime(s.baseVolume * sp.gain, now, SMOOTH_TC);
            s.panNode.pan.setTargetAtTime(sp.pan, now, SMOOTH_TC);
            if (s.wetGain) s.wetGain.gain.setTargetAtTime(s.baseVolume * sp.wet, now, SMOOTH_TC);
        }
    }

    window.PVAudio = {
        playSound:      playSound,
        startAlarm:     startAlarm,
        stopAlarm:      stopAlarm,
        updateListener: updateListener,
    };
})();
