package de.privacyguard.adhook;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Bounded, read-only cross-class relationship index for developer diagnostics.
 *
 * Edges describe declared type references only. This class never loads classes by
 * name, instantiates objects, reads field values, invokes methods, or changes app state.
 */
public final class MemberProfileGraph {
    public enum ReferenceKind { FIELD_TYPE, METHOD_RETURN, METHOD_PARAMETER }

    public static final class Node {
        public final String className;
        public final boolean memberCandidate;
        public final int profileScore;
        Node(MemberClassProfile.Result profile) {
            className = profile.className;
            memberCandidate = profile.isCandidate();
            profileScore = profile.score;
        }
    }

    public static final class Edge {
        public final String fromClass;
        public final String toClass;
        public final ReferenceKind kind;
        public final int occurrences;
        Edge(String from, String to, ReferenceKind kind, int occurrences) {
            this.fromClass = from;
            this.toClass = to;
            this.kind = kind;
            this.occurrences = occurrences;
        }
    }

    public static final class Result {
        public final List<Node> nodes;
        public final List<Edge> edges;
        Result(List<Node> nodes, List<Edge> edges) {
            this.nodes = Collections.unmodifiableList(nodes);
            this.edges = Collections.unmodifiableList(edges);
        }
        public List<Edge> edgesFrom(String className) {
            List<Edge> found = new ArrayList<>();
            for (Edge edge : edges) if (edge.fromClass.equals(className)) found.add(edge);
            return Collections.unmodifiableList(found);
        }
    }

    private static final int MAX_CLASSES = 512;
    private static final int MAX_MEMBERS = 128;
    private MemberProfileGraph() {}

    /** Builds an index over the supplied classes; input order is preserved. */
    public static Result build(Iterable<Class<?>> classes) {
        if (classes == null) throw new IllegalArgumentException("classes required");
        List<Class<?>> input = new ArrayList<>();
        for (Class<?> type : classes) {
            if (type == null) continue;
            if (input.size() >= MAX_CLASSES) break;
            if (!input.contains(type)) input.add(type);
        }

        Map<Class<?>, Node> indexed = new LinkedHashMap<>();
        for (Class<?> type : input) indexed.put(type, new Node(MemberClassProfile.inspect(type)));

        List<Edge> edges = new ArrayList<>();
        for (Class<?> source : input) {
            Map<String, int[]> counts = new LinkedHashMap<>();
            try {
                Field[] fields = source.getDeclaredFields();
                for (int i = 0; i < fields.length && i < MAX_MEMBERS; i++) {
                    Field field = fields[i];
                    if (field.isSynthetic()) continue;
                    addReference(counts, indexed, field.getType(), 0);
                }
            } catch (Throwable ignored) { }

            try {
                Method[] methods = source.getDeclaredMethods();
                for (int i = 0; i < methods.length && i < MAX_MEMBERS; i++) {
                    Method method = methods[i];
                    if (method.isSynthetic() || method.isBridge()) continue;
                    addReference(counts, indexed, method.getReturnType(), 1);
                    Class<?>[] parameters = method.getParameterTypes();
                    for (Class<?> parameter : parameters) addReference(counts, indexed, parameter, 2);
                }
            } catch (Throwable ignored) { }

            for (Map.Entry<String, int[]> entry : counts.entrySet()) {
                int[] values = entry.getValue();
                for (ReferenceKind kind : ReferenceKind.values()) {
                    int count = values[kind.ordinal()];
                    if (count > 0) edges.add(new Edge(source.getName(), entry.getKey(), kind, count));
                }
            }
        }

        List<Node> nodes = new ArrayList<>(indexed.values());
        return new Result(nodes, edges);
    }

    private static void addReference(Map<String, int[]> counts, Map<Class<?>, Node> indexed,
                                     Class<?> referenced, int kind) {
        if (referenced == null) return;
        while (referenced.isArray()) referenced = referenced.getComponentType();
        if (referenced.isPrimitive() || referenced.isInterface() && !indexed.containsKey(referenced)) return;
        if (!indexed.containsKey(referenced)) return;
        int[] values = counts.get(referenced.getName());
        if (values == null) {
            values = new int[ReferenceKind.values().length];
            counts.put(referenced.getName(), values);
        }
        values[kind]++;
    }
}
