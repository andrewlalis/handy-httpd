/**
 * An implementation of a multi-valued mapping, where one key may map to zero,
 * one, or many values.
 */
module handy_httpd.components.multivalue_map;

import std.typecons : Nullable, nullable;

/**
 * A multi-valued mapping, where a key value may map to zero, one, or many
 * values.
 */
struct MultiValueMap(KeyType, ValueType) {
    static struct Entry {
        KeyType key;
        ValueType[] values;
    }

    private Entry[] entries;

    private Nullable!Entry getEntry(KeyType k) {
        foreach (Entry entry; entries) {
            if (entry.key == k) return nullable(entry);
        }
        return Nullable!Entry.init;
    }

    ValueType[] get(KeyType k) {
        // TODO: Use faster method instead!
        auto entry = getEntry(k);
        if (entry.isNull()) {
            return [];
        }
        return entry.get().values;
    }

    void add(KeyType k, ValueType v) {
        auto entry = getEntry(k);
        if (entry.isNull) {
            entries ~= Entry(k, [v]);
        }
    }
}

/// The string => string mapping is a common usecase, so an alias is defined.
alias StringMultiValueMap = MultiValueMap!(string, string);
