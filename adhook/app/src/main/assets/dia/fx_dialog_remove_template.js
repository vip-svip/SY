/* FX Dia ViewGroup match-and-remove hook.
 * Destructive UI action. Inert until explicit rules are added and manually
 * injected into a selected application owned by or authorized to the user.
 */
(function () {
    'use strict';
    var ALERT_KEYWORD_PATTERNS = [];
    var ALERT_VIEW_IDS = [];
    var REMOVE_DELAY_MS = 100;
    var ALLOW_ANY_PARENT = false;
    var MAX_TREE_NODES = 1500;
    var MAX_TREE_DEPTH = 28;
    var MAX_REMOVE_PER_PROCESS = 5;
    var MAX_RECHECKS = 8;
    var MAX_PENDING_ROOTS = 64;

    if (!ALERT_KEYWORD_PATTERNS.length && !ALERT_VIEW_IDS.length) {
        send('[DIA_VIEWGROUP] disabled: configure an explicit regex or resource ID before injection');
        return;
    }
    var patterns = [];
    ALERT_KEYWORD_PATTERNS.forEach(function (value) {
        var raw = String(value || '').trim();
        if (!raw || raw.length > 160) return;
        try { patterns.push(new RegExp(raw, 'i')); }
        catch (_) { send('[DIA_VIEWGROUP] ignored invalid regular expression'); }
    });
    var ids = ALERT_VIEW_IDS.map(function (value) { return String(value || '').trim(); })
        .filter(function (value) { return value.length > 0 && value.length <= 160; });
    if (!patterns.length && !ids.length) {
        send('[DIA_VIEWGROUP] disabled: no valid rules remain');
        return;
    }

    Java.perform(function () {
        var Group = Java.use('android.view.ViewGroup');
        var TextView = Java.use('android.widget.TextView');
        var System = Java.use('java.lang.System');
        var pending = Object.create(null);
        var pendingCount = 0;
        var removed = 0;

        // Legacy default scope: inspect direct additions to DecorView or
        // android.R.id.content. Never climb from nested addView and risk
        // deleting an entire Activity content hierarchy on an incidental match.
        function eligibleParent(parent) {
            if (ALLOW_ANY_PARENT) return true;
            try {
                var name = String(parent.getClass().getName());
                return name.indexOf('DecorView') >= 0 || Number(parent.getId()) === 0x01020002;
            } catch (_) { return false; }
        }

        function findMatch(root) {
            var queue = [{ view: root, depth: 0 }];
            var cursor = 0;
            var visited = 0;
            while (cursor < queue.length && visited < MAX_TREE_NODES) {
                var item = queue[cursor++];
                var view = item.view;
                if (!view) continue;
                visited++;
                try {
                    var numericId = Number(view.getId());
                    if (numericId > 0) {
                        var entryName = '';
                        try { entryName = String(view.getResources().getResourceEntryName(numericId)); }
                        catch (_) { entryName = String(numericId); }
                        if (ids.indexOf(entryName) >= 0 || ids.indexOf(String(numericId)) >= 0)
                            return { kind: 'id' };
                    }
                } catch (_) {}
                if (patterns.length) {
                    try {
                        if (TextView.class.isAssignableFrom(view.getClass())) {
                            var label = String(Java.cast(view, TextView).getText() || '');
                            for (var i = 0; i < patterns.length; i++) {
                                patterns[i].lastIndex = 0;
                                if (patterns[i].test(label)) return { kind: 'regex' };
                            }
                        }
                    } catch (_) {}
                }
                if (item.depth >= MAX_TREE_DEPTH) continue;
                try {
                    if (Group.class.isAssignableFrom(view.getClass())) {
                        var group = Java.cast(view, Group);
                        var waiting = queue.length - cursor;
                        var capacity = Math.max(0, MAX_TREE_NODES - visited - waiting);
                        var count = Math.min(Number(group.getChildCount()), capacity);
                        for (var n = 0; n < count; n++) {
                            var child = group.getChildAt(n);
                            if (child) queue.push({ view: child, depth: item.depth + 1 });
                        }
                    }
                } catch (_) {}
            }
            return null;
        }

        function inspect(parent, child, key, remaining) {
            Java.scheduleOnMainThread(function () {
                try {
                    if (removed >= MAX_REMOVE_PER_PROCESS) {
                        delete pending[key];
                        pendingCount = Math.max(0, pendingCount - 1);
                        return;
                    }
                    var currentParent = child.getParent();
                    if (!currentParent || String(System.identityHashCode(currentParent))
                            !== String(System.identityHashCode(parent))) {
                        delete pending[key];
                        pendingCount = Math.max(0, pendingCount - 1);
                        return;
                    }
                    var match = findMatch(child);
                    if (match) {
                        parent.removeView(child);
                        removed++;
                        delete pending[key];
                        pendingCount = Math.max(0, pendingCount - 1);
                        send('[DIA_VIEWGROUP] removed matched root child kind=' + match.kind
                                + ' removed=' + removed);
                        return;
                    }
                    if (remaining > 0) {
                        setTimeout(function () {
                            Java.perform(function () { inspect(parent, child, key, remaining - 1); });
                        }, REMOVE_DELAY_MS);
                    } else {
                        delete pending[key];
                        pendingCount = Math.max(0, pendingCount - 1);
                    }
                } catch (_) {
                    delete pending[key];
                    pendingCount = Math.max(0, pendingCount - 1);
                }
            });
        }

        var hooks = 0;
        try {
            Group.addView.overloads.forEach(function (overload) {
                var args = overload.argumentTypes || [];
                if (!args.length || String(args[0].className) !== 'android.view.View') return;
                overload.implementation = function () {
                    var child = arguments[0];
                    var result = overload.apply(this, arguments);
                    if (!child || !eligibleParent(this) || removed >= MAX_REMOVE_PER_PROCESS
                            || pendingCount >= MAX_PENDING_ROOTS) return result;
                    try {
                        var parent = Java.retain(this);
                        var retainedChild = Java.retain(child);
                        var key = String(System.identityHashCode(retainedChild));
                        if (!pending[key]) {
                            pending[key] = true;
                            pendingCount++;
                            setTimeout(function () {
                                Java.perform(function () {
                                    inspect(parent, retainedChild, key, MAX_RECHECKS);
                                });
                            }, REMOVE_DELAY_MS);
                        }
                    } catch (_) {}
                    return result;
                };
                hooks++;
            });
        } catch (_) {}
        send('[DIA_VIEWGROUP] installed addViewHooks=' + hooks
                + ' rootOnly=' + (!ALLOW_ANY_PARENT)
                + ' maxNodes=' + MAX_TREE_NODES + ' maxDepth=' + MAX_TREE_DEPTH
                + ' maxRemovals=' + MAX_REMOVE_PER_PROCESS
                + ' maxRetries=' + MAX_RECHECKS
                + ' maxPending=' + MAX_PENDING_ROOTS
                + ' rules=' + (patterns.length + ids.length));
    });
})();
