#ifndef TAGLIB_INTEROP_H
#define TAGLIB_INTEROP_H

// Thin inline C++ helpers that smooth over Swift/C++ interop limitations with
// TagLib's public API. These are NOT a C ABI bridge -- they take and return
// TagLib C++ types (and std::string) by value and are consumed directly from
// the TagLibSwiftCxx interop module. They exist because:
//
//  * TagLib::AudioProperties and TagLib::Tag are ABSTRACT (pure-virtual) base
//    classes. Swift/C++ interop does not import abstract classes as usable
//    Swift types, so a Swift caller cannot dereference the `AudioProperties*` /
//    `Tag*` that FileRef hands back, nor name AudioProperties::ReadStyle. These
//    helpers do the dereference on the C++ side and return concrete values.
//
//  * FileRef's convenient `FileRef(FileName, bool, ReadStyle)` constructor has a
//    default argument (AudioProperties::Average) referencing that un-importable
//    abstract type, so interop drops the constructor entirely. openFile() calls
//    it from C++ where the default resolves normally.
//
//  * TagLib::PropertyMap is a Map<String, StringList>. Rather than rely on the
//    (uncertain) Swift import of std::map/std::list iterators, the small
//    copyable helper classes PropertyMapAccess / PropertyMapBuilder flatten the
//    crossing into value-returning, index-addressed accessors. Both are concrete
//    copyable value types, so they import on the value-type path (no reference
//    types => the iOS 13 / macOS 10.15 floor is preserved).

#include <cstring>
#include <string>
#include <vector>

#include "taglib/fileref.h"
#include "taglib/tfile.h"
#include "taglib/tag.h"
#include "taglib/tstring.h"
#include "taglib/tstringlist.h"
#include "taglib/tpropertymap.h"
#include "taglib/tbytevector.h"
#include "taglib/tvariant.h"
#include "taglib/tlist.h"
#include "taglib/audioproperties.h"

namespace TagLibInterop {

// ---------------------------------------------------------------------------
// File handle
// ---------------------------------------------------------------------------

// Construct a FileRef from a UTF-8 path (default read-style resolved in C++).
inline TagLib::FileRef openFile(const char *path) {
    return TagLib::FileRef(path);
}

// Whether the underlying file was parsed successfully.
inline bool isValid(const TagLib::FileRef &ref) {
    return !ref.isNull() && ref.file() != nullptr && ref.file()->isValid();
}

// Persist pending tag changes to disk. Returns false on failure.
inline bool save(TagLib::FileRef &ref) {
    return !ref.isNull() && ref.save();
}

// ---------------------------------------------------------------------------
// AudioProperties (read-only) -- dereferenced on the C++ side
// ---------------------------------------------------------------------------

// Whether the file exposes an AudioProperties object at all. FileRef only
// synthesizes one for files it could parse audio from, so this is false for a
// null ref (and, in principle, a parsed file with no decodable audio stream).
inline bool hasAudioProperties(const TagLib::FileRef &ref) {
    return !ref.isNull() && ref.audioProperties() != nullptr;
}

inline int lengthInSeconds(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    return p ? p->lengthInSeconds() : -1;
}

inline int lengthInMilliseconds(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    return p ? p->lengthInMilliseconds() : -1;
}

inline int bitrate(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    return p ? p->bitrate() : -1;
}

inline int sampleRate(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    return p ? p->sampleRate() : -1;
}

inline int channels(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    return p ? p->channels() : -1;
}

// ---------------------------------------------------------------------------
// Base Tag get/set -- dereferenced on the C++ side.
// Getters return std::string (UTF-8), which CxxStdlib bridges to Swift.String.
// ---------------------------------------------------------------------------

inline std::string title(const TagLib::FileRef &ref) {
    const TagLib::Tag *t = ref.tag();
    return t ? t->title().to8Bit(true) : std::string();
}

inline std::string artist(const TagLib::FileRef &ref) {
    const TagLib::Tag *t = ref.tag();
    return t ? t->artist().to8Bit(true) : std::string();
}

inline std::string album(const TagLib::FileRef &ref) {
    const TagLib::Tag *t = ref.tag();
    return t ? t->album().to8Bit(true) : std::string();
}

inline std::string comment(const TagLib::FileRef &ref) {
    const TagLib::Tag *t = ref.tag();
    return t ? t->comment().to8Bit(true) : std::string();
}

inline std::string genre(const TagLib::FileRef &ref) {
    const TagLib::Tag *t = ref.tag();
    return t ? t->genre().to8Bit(true) : std::string();
}

inline unsigned int year(const TagLib::FileRef &ref) {
    const TagLib::Tag *t = ref.tag();
    return t ? t->year() : 0;
}

inline unsigned int track(const TagLib::FileRef &ref) {
    const TagLib::Tag *t = ref.tag();
    return t ? t->track() : 0;
}

inline void setTitle(TagLib::FileRef &ref, const char *value) {
    if (TagLib::Tag *t = ref.tag()) t->setTitle(TagLib::String(value, TagLib::String::UTF8));
}

inline void setArtist(TagLib::FileRef &ref, const char *value) {
    if (TagLib::Tag *t = ref.tag()) t->setArtist(TagLib::String(value, TagLib::String::UTF8));
}

inline void setAlbum(TagLib::FileRef &ref, const char *value) {
    if (TagLib::Tag *t = ref.tag()) t->setAlbum(TagLib::String(value, TagLib::String::UTF8));
}

inline void setComment(TagLib::FileRef &ref, const char *value) {
    if (TagLib::Tag *t = ref.tag()) t->setComment(TagLib::String(value, TagLib::String::UTF8));
}

inline void setGenre(TagLib::FileRef &ref, const char *value) {
    if (TagLib::Tag *t = ref.tag()) t->setGenre(TagLib::String(value, TagLib::String::UTF8));
}

inline void setYear(TagLib::FileRef &ref, unsigned int value) {
    if (TagLib::Tag *t = ref.tag()) t->setYear(value);
}

inline void setTrack(TagLib::FileRef &ref, unsigned int value) {
    if (TagLib::Tag *t = ref.tag()) t->setTrack(value);
}

// ---------------------------------------------------------------------------
// PropertyMap -- the universal all-text-tags interface (TagLib::PropertyMap).
//
// PropertyMapAccess snapshots the file's PropertyMap once (O(n)) and exposes it
// as flat, index-addressed value accessors so Swift can rebuild a
// [String: [String]] without re-fetching (no O(n^2)) and without importing
// std::map/std::list iterators.
// ---------------------------------------------------------------------------

class PropertyMapAccess {
public:
    explicit PropertyMapAccess(const TagLib::FileRef &ref) {
        if (!ref.isNull()) {
            // FileRef::properties() forwards to the wrapped File, which reads the
            // format's tags correctly (the canonical PropertyMap read path).
            map_ = ref.properties();
        }
        rebuildKeys();
    }

    // Snapshot an already-computed PropertyMap directly. Used to surface the
    // "unsupported" map that FileRef::setProperties() returns (the keys/values
    // the format could not store) back to Swift via the same flat, value-type,
    // index-addressed accessors used for reads.
    explicit PropertyMapAccess(const TagLib::PropertyMap &map) : map_(map) {
        rebuildKeys();
    }

    unsigned int keyCount() const {
        return keys_.size();
    }

    std::string key(unsigned int i) const {
        return keys_[i].to8Bit(true);
    }

    unsigned int valueCount(unsigned int i) const {
        auto it = map_.find(keys_[i]);
        return it != map_.end() ? it->second.size() : 0;
    }

    std::string value(unsigned int i, unsigned int j) const {
        auto it = map_.find(keys_[i]);
        return it != map_.end() ? it->second[j].to8Bit(true) : std::string();
    }

private:
    void rebuildKeys() {
        keys_.clear();
        for (auto it = map_.begin(); it != map_.end(); ++it) {
            keys_.append(it->first);
        }
    }

    TagLib::PropertyMap map_;
    TagLib::StringList keys_;
};

// PropertyMapBuilder accumulates a PropertyMap from Swift (append one value at a
// time, since crossing a nested [String: [String]] wholesale is awkward). Apply
// it with the free function applyProperties(), then save() to persist.
class PropertyMapBuilder {
public:
    void append(const char *key, const char *value) {
        // Keys are ASCII PropertyMap identifiers; construct with the default
        // (Latin1) ctor so they compare equal to TagLib's built-in key table.
        // Values may contain UTF-8, so decode those as UTF-8.
        map_[TagLib::String(key)]
            .append(TagLib::String(value, TagLib::String::UTF8));
    }

    // Ensure a key exists even with zero values (records an explicit empty list).
    void ensureKey(const char *key) {
        const TagLib::String k(key);
        if (!map_.contains(k)) {
            map_[k] = TagLib::StringList();
        }
    }

    const TagLib::PropertyMap &map() const { return map_; }

private:
    TagLib::PropertyMap map_;
};

// Apply a builder's PropertyMap to a file. Implemented as a free function taking
// the FileRef by reference: a Swift `inout` FileRef passed to a *member* method
// of a Swift-held C++ value did not propagate newly created frames (existing
// frames updated, but e.g. a new COMPOSER/TCOM frame was silently dropped),
// whereas a free function receiving the same `inout` writes correctly.
// FileRef::setProperties() RETURNS the subset of properties the format could
// not store (unsupported/rejected keys). Ignoring it silently drops data, so we
// surface it back to Swift as a PropertyMapAccess snapshot (empty => full
// success). On a null ref there is nothing to store; every requested key is
// effectively unsupported, so echo the builder's map back as rejected.
inline PropertyMapAccess applyProperties(TagLib::FileRef &ref,
                                         const PropertyMapBuilder &builder) {
    if (ref.isNull()) {
        return PropertyMapAccess(builder.map());
    }
    return PropertyMapAccess(ref.setProperties(builder.map()));
}

// ---------------------------------------------------------------------------
// Cover art -- complex properties under the "PICTURE" key
// (FileRef::complexProperties / setComplexProperties, a List<VariantMap>).
//
// Same value-type crossing strategy as PropertyMap: PictureListAccess snapshots
// the pictures once and flattens each VariantMap's "data" (ByteVector),
// "mimeType", "description" and "pictureType" (String) fields into stable,
// index-addressed accessors. Binary picture bytes are copied into std::string
// buffers held by the access object, so the pointers returned by pictureData()
// stay valid for the object's lifetime (a temporary ByteVector's data() would
// dangle). Both helpers are concrete copyable value types (floor preserved).
// ---------------------------------------------------------------------------

class PictureListAccess {
public:
    explicit PictureListAccess(const TagLib::FileRef &ref) {
        if (ref.isNull()) return;
        const TagLib::List<TagLib::VariantMap> pics =
            ref.complexProperties("PICTURE");
        for (auto it = pics.begin(); it != pics.end(); ++it) {
            const TagLib::VariantMap &m = *it;
            Entry e;
            const TagLib::ByteVector bv = variantByteVector(m, "data");
            e.data.assign(bv.data(), bv.size());
            e.mimeType = variantString(m, "mimeType");
            e.description = variantString(m, "description");
            e.pictureType = variantString(m, "pictureType");
            entries_.push_back(std::move(e));
        }
    }

    unsigned int count() const {
        return static_cast<unsigned int>(entries_.size());
    }

    unsigned int pictureDataSize(unsigned int i) const {
        return static_cast<unsigned int>(entries_[i].data.size());
    }

    // Copy picture i's raw bytes into a Swift-provided buffer of at least
    // pictureDataSize(i) bytes. (Swift/C++ interop refuses to import a method
    // that returns an interior pointer, so the crossing is a copy instead.)
    void copyPictureData(unsigned int i, char *dest) const {
        const std::string &d = entries_[i].data;
        if (!d.empty()) {
            std::memcpy(dest, d.data(), d.size());
        }
    }

    std::string mimeType(unsigned int i) const { return entries_[i].mimeType; }
    std::string description(unsigned int i) const { return entries_[i].description; }
    std::string pictureType(unsigned int i) const { return entries_[i].pictureType; }

private:
    struct Entry {
        std::string data;
        std::string mimeType;
        std::string description;
        std::string pictureType;
    };

    static TagLib::ByteVector variantByteVector(const TagLib::VariantMap &m,
                                                const char *key) {
        auto it = m.find(TagLib::String(key));
        return it != m.end() ? it->second.toByteVector() : TagLib::ByteVector();
    }

    static std::string variantString(const TagLib::VariantMap &m,
                                     const char *key) {
        auto it = m.find(TagLib::String(key));
        return it != m.end() ? it->second.toString().to8Bit(true) : std::string();
    }

    std::vector<Entry> entries_;
};

// Accumulates a List<VariantMap> of pictures from Swift, one at a time. Apply
// with the free function applyPictures() (free function for the same inout-
// FileRef reason documented on applyProperties), then save() to persist.
class PictureListBuilder {
public:
    void append(const char *data, unsigned int dataSize,
                const char *mimeType, const char *description,
                const char *pictureType) {
        TagLib::VariantMap m;
        m.insert("data", TagLib::Variant(TagLib::ByteVector(data, dataSize)));
        m.insert("mimeType", TagLib::Variant(TagLib::String(mimeType, TagLib::String::UTF8)));
        m.insert("description", TagLib::Variant(TagLib::String(description, TagLib::String::UTF8)));
        m.insert("pictureType", TagLib::Variant(TagLib::String(pictureType, TagLib::String::UTF8)));
        list_.append(m);
    }

    const TagLib::List<TagLib::VariantMap> &list() const { return list_; }

private:
    TagLib::List<TagLib::VariantMap> list_;
};

// Apply a builder's picture list to a file (free function -- see applyProperties).
inline bool applyPictures(TagLib::FileRef &ref, const PictureListBuilder &builder) {
    if (ref.isNull()) return false;
    return ref.setComplexProperties("PICTURE", builder.list());
}

} // namespace TagLibInterop

#endif /* TAGLIB_INTEROP_H */
