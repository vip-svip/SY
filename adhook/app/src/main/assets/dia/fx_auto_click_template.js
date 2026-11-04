/* FX Dia regex/resource-ID automatic click hook.
 * Inert until explicit rules are added and the user manually injects it.
 * Only use against apps you own or are authorized to test.
 */
(function () {
    'use strict';
    var KEYWORD_PATTERNS = []; // TextView regular expressions.
    var VIEW_IDS = [];         // Resource entry names or decimal resource IDs.
    var CLICK_DELAY_MS = 0;
    var SCAN_DELAY_MS = 120;
    var MAX_TREE_NODES = 1500;
    var MAX_TREE_DEPTH = 28;
    var MAX_CLICKS_PER_PROCESS = 8;

    if (!KEYWORD_PATTERNS.length && !VIEW_IDS.length) {
        send('[DIA_AUTOCLICK] disabled: add an explicit regex or resource ID before injection');
        return;
    }
    var delayMs = Math.max(0, Math.min(10000, Number(CLICK_DELAY_MS) || 0));
    var patterns = [];
    KEYWORD_PATTERNS.forEach(function (value) {
        var pattern = String(value || '').trim();
        if (!pattern || pattern.length > 160) return;
        try { patterns.push(new RegExp(pattern, 'i')); }
        catch (_) { send('[DIA_AUTOCLICK] ignored an invalid regular expression'); }
    });
    var ids = VIEW_IDS.map(function (value) { return String(value || '').trim(); })
        .filter(function (value) { return value.length > 0 && value.length <= 160; });
    if (!patterns.length && !ids.length) {
        send('[DIA_AUTOCLICK] disabled: no valid matching rule remains');
        return;
    }
    Java.perform(function () {
        var Activity = Java.use('android.app.Activity');
        var Group = Java.use('android.view.ViewGroup');
        var TextView = Java.use('android.widget.TextView');
        var System = Java.use('java.lang.System');
        var seen = Object.create(null), scheduled = 0, scanCount = 0;

        function match(view) {
            var numericId = -1, entry = '';
            try {
                numericId = Number(view.getId());
                if (numericId > 0) {
                    try { entry = String(view.getResources().getResourceEntryName(numericId)); }
                    catch (_) { entry = String(numericId); }
                }
            } catch (_) {}
            if (entry && ids.indexOf(entry) >= 0) return { kind: 'id', id: entry };
            if (numericId > 0 && ids.indexOf(String(numericId)) >= 0)
                return { kind: 'id', id: String(numericId) };
            if (patterns.length) {
                try {
                    if (TextView.class.isAssignableFrom(view.getClass())) {
                        var label = String(Java.cast(view, TextView).getText() || '');
                        for (var i = 0; i < patterns.length; i++) {
                            patterns[i].lastIndex = 0;
                            if (patterns[i].test(label)) return { kind: 'regex', id: entry || 'no-id' };
                        }
                    }
                } catch (_) {}
            }
            return null;
        }
        function click(view, rule) {
            try {
                if (!view.isClickable() || !view.isEnabled() || scheduled >= MAX_CLICKS_PER_PROCESS) return;
                var key = String(System.identityHashCode(view));
                if (seen[key]) return;
                seen[key] = true;
                scheduled++;
                var retained = Java.retain(view);
                setTimeout(function () {
                    Java.perform(function () {
                        Java.scheduleOnMainThread(function () {
                            try {
                                if (!retained.isShown() || !retained.isEnabled()
                                        || !retained.isClickable() || retained.getWindowVisibility() !== 0) {
                                    send('[DIA_AUTOCLICK] skipped view no longer visible/clickable id=' + rule.id);
                                    return;
                                }
                                var result = retained.performClick();
                                send('[DIA_AUTOCLICK] performed match=' + rule.kind
                                        + ' view=' + String(retained.getClass().getName())
                                        + ' id=' + rule.id + ' result=' + result);
                            } catch (error) {
                                send('[DIA_AUTOCLICK] click failed type='
                                        + (error && error.$className ? error.$className : 'Error'));
                            }
                        });
                    });
                }, delayMs);
            } catch (_) {}
        }
        function scan(root) {
            if (!root || scanCount++ >= 500) return;
            var queue = [{view:root,depth:0}], cursor = 0, visited = 0;
            while (cursor < queue.length && visited < MAX_TREE_NODES
                    && scheduled < MAX_CLICKS_PER_PROCESS) {
                var item = queue[cursor++], view = item.view;
                if (!view) continue;
                visited++;
                var rule = match(view);
                if (rule) click(view, rule);
                if (item.depth >= MAX_TREE_DEPTH) continue;
                try {
                    if (Group.class.isAssignableFrom(view.getClass())) {
                        var group = Java.cast(view, Group);
                        var waiting = queue.length - cursor;
                        var capacity = Math.max(0, MAX_TREE_NODES - visited - waiting);
                        var count = Math.min(Number(group.getChildCount()), capacity);
                        for (var i = 0; i < count; i++) {
                            var child = group.getChildAt(i);
                            if (child) queue.push({view:child,depth:item.depth+1});
                        }
                    }
                } catch (_) {}
            }
        }
        function scheduleScan(root) {
            if (!root) return;
            var retained;
            try { retained = Java.retain(root); } catch (_) { return; }
            setTimeout(function () {
                Java.perform(function () {
                    Java.scheduleOnMainThread(function () {
                        try { scan(retained); } catch (_) {}
                    });
                });
            }, SCAN_DELAY_MS);
        }
        var addViewHooks = 0;
        try {
            Group.addView.overloads.forEach(function (overload) {
                var args = overload.argumentTypes || [];
                if (!args.length || String(args[0].className) !== 'android.view.View') return;
                overload.implementation = function () {
                    var child = arguments[0], result = overload.apply(this, arguments);
                    scheduleScan(child);
                    return result;
                };
                addViewHooks++;
            });
        } catch (_) {}
        try {
            var resume = Activity.onResume.overload();
            resume.implementation = function () {
                var result = resume.call(this);
                try { scheduleScan(this.getWindow().getDecorView()); } catch (_) {}
                return result;
            };
        } catch (_) {}
        send('[DIA_AUTOCLICK] installed addViewHooks=' + addViewHooks
                + ' delayMs=' + delayMs + ' maxNodes=' + MAX_TREE_NODES
                + ' maxDepth=' + MAX_TREE_DEPTH + ' maxClicks=' + MAX_CLICKS_PER_PROCESS
                + ' rules=' + (patterns.length + ids.length));
    });
})();
