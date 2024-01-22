/**
 * An implementation of a multi-valued mapping, where one key may map to zero,
 * one, or many values.
 */
module handy_httpd.components.multivalue_map;

import handy_httpd.components.optional;

/**
 * A multi-valued mapping, where a key value may map to zero, one, or many
 * values.
 */
struct MultiValueMap(KeyType, ValueType, alias KeySort = (a, b) => a < b) {
    /// The internal structure used to store each key and set of values.
    static struct Entry {
        /// The key for this entry.
        KeyType key;
        /// The list of values associated with this entry's key.
        ValueType[] values;
    }

    /// The internal, sorted array of entries.
    private Entry[] entries;

    /**
     * Finds the index of the entry with a given key in the internal array.
     * Params:
     *   k = The key to search for.
     * Returns: The index if it was found, or -1 if it doesn't exist.
     */
    private long indexOf(KeyType k) {
        if (entries.length == 0) return -1;
        if (entries.length == 1) {
            return entries[0].key == k ? 0 : -1;
        }
        size_t startIdx = 0;
        size_t endIdx = entries.length - 1;
        while (startIdx <= endIdx) {
            size_t mid = startIdx + (endIdx - startIdx) / 2;
            if (entries[mid].key == k) return mid;
            if (KeySort(entries[mid].key, k)) {
                startIdx = mid + 1;
            } else {
                endIdx = mid - 1;
            }
        }
        return -1;
    }

    /**
     * Attempts to get the entry for a given key. Complexity is O(log(keyCount)).
     * Params:
     *   k = The key to look for.
     * Returns: An optional that may contain the entry that was found.
     */
    private Optional!Entry getEntry(KeyType k) {
        long idx = indexOf(k);
        if (idx == -1) return Optional!Entry.empty();
        return Optional!Entry.of(entries[idx]);
    }

    /**
     * Gets the number of unique keys in this map.
     * Returns: The number of unique keys in this map.
     */
    size_t length() {
        return entries.length;
    }

    /**
     * Determines if this map contains a value for the given key.
     * Params:
     *   k = The key to search for.
     * Returns: True if at least one value exists for the given key.
     */
    bool contains(KeyType k) {
        Optional!Entry optionalEntry = getEntry(k);
        return !optionalEntry.isNull && optionalEntry.value.values.length > 0;
    }

    /**
     * Gets all values associated with a given key.
     * Params:
     *   k = The key to get the values of.
     * Returns: The values associated with the given key, or an empty array if
     * no values exist for the key.
     */
    ValueType[] getAll(KeyType k) {
        return getEntry(k).map!(e => e.values).orElse([]);
    }

    /**
     * Gets the first value associated with a given key, as per the order in
     * which the values were inserted.
     * Params:
     *   k = The key to get the first value of.
     * Returns: An optional contains the value, if there is at least one value
     * for the given key.
     */
    Optional!ValueType getFirst(KeyType k) {
        Optional!Entry optionalEntry = getEntry(k);
        if (optionalEntry.isNull || optionalEntry.value.values.length == 0) {
            return Optional!ValueType.empty();
        }
        return Optional!ValueType.of(optionalEntry.value.values[0]);
    }

    /**
     * Adds a single key -> value pair to the map.
     * Params:
     *   k = The key.
     *   v = The value associated with the key.
     */
    void add(KeyType k, ValueType v) {
        auto optionalEntry = getEntry(k);
        if (optionalEntry.isNull) {
            entries ~= Entry(k, [v]);
            import std.algorithm.sorting : sort;
            sort!((a, b) => KeySort(a.key, b.key))(entries);
        } else {
            optionalEntry.value.values ~= v;
        }
    }

    /**
     * Clears this map of all values.
     */
    void clear() {
        entries.length = 0;
    }

    /**
     * Removes a key from the map.
     * Params:
     *   k = The key to remove.
     */
    void remove(KeyType k) {
        long idx = indexOf(k);
        if (idx == -1) return;
        if (entries.length == 1) {
            clear();
            return;
        }
        if (idx + 1 < entries.length) {
            entries[idx .. $ - 1] = entries[idx + 1 .. $];
        }
        entries.length = entries.length - 1;
    }

    /**
     * Gets this multivalue map as an associative array, where each key is
     * mapped to a list of values.
     * Returns: The associative array.
     */
    ValueType[][KeyType] asAssociativeArray() {
        ValueType[][KeyType] aa;
        foreach (Entry entry; entries) {
            aa[entry.key] = entry.values.dup;
        }
        return aa;
    }

    /**
     * Constructs a multivalued map from an associative array.
     * Params:
     *   aa = The associative array to use.
     * Returns: The multivalued map.
     */
    static MultiValueMap!(KeyType, ValueType, KeySort) fromAssociativeArray(ValueType[][KeyType] aa) {
        MultiValueMap!(KeyType, ValueType, KeySort) m;
        foreach (KeyType k, ValueType[] values; aa) {
            foreach (ValueType v; values) {
                m.add(k, v);
            }
        }
        return m;
    }

    /**
     * Constructs a multivalued map from an associative array of single values.
     * Params:
     *   aa = The associative array to use.
     * Returns: The multivalued map.
     */
    static MultiValueMap!(KeyType, ValueType, KeySort) fromAssociativeArray(ValueType[KeyType] aa) {
        MultiValueMap!(KeyType, ValueType, KeySort) m;
        foreach (KeyType k, ValueType v; aa) {
            m.add(k, v);
        }
        return m;
    }

    /**
     * An efficient builder that can be used to construct a multivalued map
     * with successive `add` calls, which is more efficient than doing so
     * directly due to the builder's deferred sorting.
     */
    static struct Builder {
        import std.array;

        alias MapType = MultiValueMap!(KeyType, ValueType, KeySort);

        private MapType m;
        private RefAppender!(Entry[]) entryAppender;

        /**
         * Adds a key -> value pair to the builder's map.
         * Params:
         *   k = The key.
         *   v = The value associated with the key.
         * Returns: A reference to the builder, for method chaining.
         */
        ref Builder add(KeyType k, ValueType v) {
            if (entryAppender.data is null) entryAppender = appender(&m.entries);
            auto optionalEntry = getEntry(k);
            if (optionalEntry.isNull) {
                entryAppender ~= Entry(k, [v]);
            } else {
                optionalEntry.value.values ~= v;
            }
            return this;
        }

        /**
         * Builds the multivalued map.
         * Returns: The map that was created.
         */
        MapType build() {
            if (m.entries.length == 0) return m;
            import std.algorithm.sorting : sort;
            sort!((a, b) => KeySort(a.key, b.key))(m.entries);
            return m;
        }

        private Optional!(MapType.Entry) getEntry(KeyType k) {
            foreach (MapType.Entry entry; m.entries) {
                if (entry.key == k) return Optional!(MapType.Entry).of(entry);
            }
            return Optional!(MapType.Entry).empty();
        }
    }

    // OPERATOR OVERLOADS below here

    /**
     * Convenience overload to get the first value for a given key. Note: this
     * will throw an exception if no values exist for the given key. To avoid
     * this, use `getFirst` and deal with the missing value yourself.
     * Params:
     *   key = The key to get the value of.
     * Returns: The first value for the given key.
     */
    ValueType opIndex(KeyType key) {
        import std.conv : to;
        return getFirst(key).orElseThrow("No values exist for key " ~ key.to!string ~ ".");
    }
}

/**
 * A multivalued map of strings, where each string key refers to zero or more
 * string values. All keys are case-sensitive.
 */
alias StringMultiValueMap = MultiValueMap!(string, string);

unittest {
    StringMultiValueMap m;
    m.add("a", "hello");
    assert(m.getFirst("a").orElseThrow == "hello");
    m.add("b", "bye");
    assert(m.getFirst("b").orElseThrow == "bye");
    assert(m.asAssociativeArray == ["a": ["hello"], "b": ["bye"]]);
    assert(m["b"] == "bye");
    m.remove("a");
    assert(!m.contains("a"));

    auto m2 = StringMultiValueMap.fromAssociativeArray(["a": "123", "b": "abc"]);
    assert(m2["a"] == "123");
    assert(m2["b"] == "abc");

    auto m3 = StringMultiValueMap.fromAssociativeArray(["a": [""], "b": [""], "c": ["hello"]]);
    assert(m3.contains("a"));
    assert(m3["a"] == "");
    assert(m3.contains("b"));
    assert(m3["b"] == "");
    assert(m3.contains("c"));
    assert(m3["c"] == "hello");
}