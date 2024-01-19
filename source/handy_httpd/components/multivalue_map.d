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
     * Attempts to get the entry for a given key. Complexity is O(log(keyCount)).
     * Params:
     *   k = The key to look for.
     * Returns: An optional that may contain the entry that was found.
     */
    private Optional!Entry getEntry(KeyType k) {
        if (entries.length == 0) return Optional!Entry.empty();
        // Simple binary search.
        size_t startIdx = 0;
        size_t endIdx = entries.length - 1;
        while (startIdx <= endIdx) {
            size_t mid = startIdx + (endIdx - startIdx) / 2;
            if (entries[mid].key == k) return Optional!Entry.of(entries[mid]);
            if (KeySort(entries[mid].key, k)) {
                startIdx = mid + 1;
            } else {
                endIdx = mid - 1;
            }
        }
        return Optional!Entry.empty();
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

/// The string => string mapping is a common usecase, so an alias is defined.
alias StringMultiValueMap = MultiValueMap!(string, string);

unittest {
    StringMultiValueMap m;
    m.add("a", "hello");
    assert(m.getFirst("a").orElseThrow == "hello");
    m.add("b", "bye");
    assert(m.getFirst("b").orElseThrow == "bye");
    assert(m.asAssociativeArray == ["a": ["hello"], "b": ["bye"]]);
}
