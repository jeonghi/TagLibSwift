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
#include "taglib/tbytevectorstream.h"
#include "taglib/tiostream.h"
#include "taglib/tvariant.h"
#include "taglib/tmap.h"
#include "taglib/tlist.h"
#include "taglib/audioproperties.h"

// Concrete AudioProperties subclasses, dynamic_cast'd on the C++ side to surface
// per-format extras (bitsPerSample, MPEG version/layer) the abstract base lacks.
#include "taglib/flacproperties.h"
#include "taglib/mpegproperties.h"
#include "taglib/mpegheader.h"
#include "taglib/wavproperties.h"
#include "taglib/aiffproperties.h"
#include "taglib/mp4properties.h"
#include "taglib/apeproperties.h"
#include "taglib/wavpackproperties.h"
#include "taglib/trueaudioproperties.h"
#include "taglib/dsfproperties.h"
#include "taglib/dsdiffproperties.h"

namespace TagLibInterop {

// ---------------------------------------------------------------------------
// File handle
// ---------------------------------------------------------------------------

// Construct a FileRef from a UTF-8 path (default read-style resolved in C++).
inline TagLib::FileRef openFile(const char *path) {
    return TagLib::FileRef(path);
}

// ---------------------------------------------------------------------------
// In-memory / IOStream I/O
//
// A ByteVectorStream that reports a synthetic name carrying the caller's file
// extension (e.g. "memory.mp3"). ByteVectorStream::name() is empty, so
// FileRef::parse() cannot detect the format by extension; overriding name()
// restores extension-based detection (with content sniffing as fallback).
// ---------------------------------------------------------------------------

class NamedByteVectorStream : public TagLib::ByteVectorStream {
public:
    NamedByteVectorStream(const TagLib::ByteVector &data, std::string name)
        : TagLib::ByteVectorStream(data), name_(std::move(name)) {}
    // FileName is `const char *` on POSIX; the returned pointer stays valid for
    // the lifetime of this object (it is the backing std::string's buffer).
    TagLib::FileName name() const override { return name_.c_str(); }
private:
    std::string name_;
};

// Owns an in-memory audio file: the ByteVectorStream MUST outlive the FileRef
// that points at it, so both live together in one heap object reached through an
// opaque handle (void*). This is deliberately NOT modeled as a Swift/C++
// reference type -- that would raise the deployment floor to iOS 16.4. Instead
// the handle crosses as a plain pointer and every operation is a free function
// returning values, preserving the iOS 13 / macOS 10.15 floor.
struct MemoryFile {
    NamedByteVectorStream stream;
    TagLib::FileRef ref;

    MemoryFile(const void *bytes, size_t len, const char *ext)
        : stream(TagLib::ByteVector(static_cast<const char *>(bytes),
                                    static_cast<unsigned int>(len)),
                 std::string("memory.") + (ext ? ext : "")),
          // FileRef does NOT take ownership of the stream (see fileref.h); this
          // struct keeps it alive alongside the FileRef.
          ref(&stream) {}
};

// Allocate a memory-backed file from a byte buffer + extension hint. Returns an
// opaque handle (never null); the caller owns it and must closeMemory() it.
inline void *openMemory(const void *bytes, size_t len, const char *ext) {
    return new MemoryFile(bytes, len, ext);
}

// A COPY of the handle's FileRef (FileRef is implicitly shared: the copy shares
// the same parsed File through a shared_ptr, so edits + save() on the copy land
// on the same in-memory stream).
inline TagLib::FileRef memoryFileRef(void *handle) {
    return static_cast<MemoryFile *>(handle)->ref;
}

// Size, in bytes, of the handle's current in-memory data (call after save()).
inline size_t memoryDataSize(void *handle) {
    const TagLib::ByteVector *bv = static_cast<MemoryFile *>(handle)->stream.data();
    return bv ? bv->size() : 0;
}

// Copy the handle's current in-memory bytes into a Swift-provided buffer of at
// least memoryDataSize(handle) bytes.
inline void memoryCopyData(void *handle, char *dest) {
    const TagLib::ByteVector *bv = static_cast<MemoryFile *>(handle)->stream.data();
    if (bv && bv->size() > 0) {
        std::memcpy(dest, bv->data(), bv->size());
    }
}

// Destroy a handle returned by openMemory().
inline void closeMemory(void *handle) {
    delete static_cast<MemoryFile *>(handle);
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

// Extended, per-format extras the abstract AudioProperties base does not expose.
// Each dynamic_cast's the concrete property object; -1 means "not applicable to
// this format" (Swift maps that to nil).

inline int bitsPerSample(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    if (!p) return -1;
    if (auto x = dynamic_cast<const TagLib::FLAC::Properties *>(p)) return x->bitsPerSample();
    if (auto x = dynamic_cast<const TagLib::RIFF::WAV::Properties *>(p)) return x->bitsPerSample();
    if (auto x = dynamic_cast<const TagLib::RIFF::AIFF::Properties *>(p)) return x->bitsPerSample();
    if (auto x = dynamic_cast<const TagLib::MP4::Properties *>(p)) return x->bitsPerSample();
    if (auto x = dynamic_cast<const TagLib::APE::Properties *>(p)) return x->bitsPerSample();
    if (auto x = dynamic_cast<const TagLib::WavPack::Properties *>(p)) return x->bitsPerSample();
    if (auto x = dynamic_cast<const TagLib::TrueAudio::Properties *>(p)) return x->bitsPerSample();
    if (auto x = dynamic_cast<const TagLib::DSF::Properties *>(p)) return x->bitsPerSample();
    if (auto x = dynamic_cast<const TagLib::DSDIFF::Properties *>(p)) return x->bitsPerSample();
    return -1; // MPEG, Vorbis, Opus, ... carry no bits-per-sample.
}

// MPEG version as the raw TagLib enum value (Version1=0, Version2=1,
// Version2_5=2, Version4=3), or -1 for non-MPEG streams.
inline int mpegVersion(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    if (auto x = dynamic_cast<const TagLib::MPEG::Properties *>(p))
        return static_cast<int>(x->version());
    return -1;
}

// MPEG layer (1-3), or -1 for non-MPEG streams.
inline int mpegLayer(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    if (auto x = dynamic_cast<const TagLib::MPEG::Properties *>(p))
        return x->layer();
    return -1;
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
// Generic complex properties
// (FileRef::complexPropertyKeys / complexProperties / setComplexProperties --
// each key maps to a List<VariantMap>, VariantMap = Map<String, Variant>).
//
// Same value-type crossing strategy as PropertyMap: snapshot once on the C++
// side and expose flat, index-addressed value accessors so Swift never imports
// std::map/std::list iterators. Cover art ("PICTURE") is just one key layered on
// top of this generic API in Swift.
// ---------------------------------------------------------------------------

// A flattened, copyable snapshot of a StringList (used for complexPropertyKeys
// and, internally, StringList-typed variant fields).
class StringListAccess {
public:
    explicit StringListAccess(const TagLib::StringList &list) {
        for (auto it = list.begin(); it != list.end(); ++it) {
            items_.push_back(it->to8Bit(true));
        }
    }
    unsigned int count() const { return static_cast<unsigned int>(items_.size()); }
    std::string at(unsigned int i) const { return items_[i]; }
private:
    std::vector<std::string> items_;
};

inline StringListAccess complexPropertyKeys(const TagLib::FileRef &ref) {
    return ref.isNull() ? StringListAccess(TagLib::StringList())
                        : StringListAccess(ref.complexPropertyKeys());
}

// Field type tags shared with the Swift ComplexValue enum. Keep in sync.
enum ComplexFieldType {
    ComplexFieldString = 0,
    ComplexFieldInt = 1,
    ComplexFieldBool = 2,
    ComplexFieldData = 3,
    ComplexFieldStringList = 4,
    ComplexFieldUnsupported = 5,
};

// Snapshots one key's List<VariantMap>, eagerly decoding every field into a flat
// per-map, per-field representation Swift can rebuild without touching C++
// containers. Binary bytes are copied into std::string buffers so the pointers
// handed back stay valid for this object's lifetime.
class ComplexPropertyAccess {
public:
    ComplexPropertyAccess(const TagLib::FileRef &ref, const char *key) {
        if (ref.isNull()) return;
        ingest(ref.complexProperties(key));
    }

    // Snapshot an already-computed List<VariantMap> (used by the round-trip and
    // unsupported-sample helpers below, and to exercise the crossing for variant
    // types no format persists to disk).
    explicit ComplexPropertyAccess(const TagLib::List<TagLib::VariantMap> &maps) {
        ingest(maps);
    }

    unsigned int mapCount() const { return static_cast<unsigned int>(maps_.size()); }
    unsigned int fieldCount(unsigned int m) const {
        return static_cast<unsigned int>(maps_[m].size());
    }
    std::string fieldKey(unsigned int m, unsigned int f) const { return maps_[m][f].key; }
    int fieldType(unsigned int m, unsigned int f) const { return maps_[m][f].type; }
    std::string fieldString(unsigned int m, unsigned int f) const { return maps_[m][f].str; }
    long long fieldInt(unsigned int m, unsigned int f) const { return maps_[m][f].i; }
    bool fieldBool(unsigned int m, unsigned int f) const { return maps_[m][f].b; }
    unsigned int fieldDataSize(unsigned int m, unsigned int f) const {
        return static_cast<unsigned int>(maps_[m][f].data.size());
    }
    void fieldCopyData(unsigned int m, unsigned int f, char *dest) const {
        const std::string &d = maps_[m][f].data;
        if (!d.empty()) std::memcpy(dest, d.data(), d.size());
    }
    unsigned int fieldListCount(unsigned int m, unsigned int f) const {
        return static_cast<unsigned int>(maps_[m][f].list.size());
    }
    std::string fieldListValue(unsigned int m, unsigned int f, unsigned int i) const {
        return maps_[m][f].list[i];
    }

private:
    struct Field {
        std::string key;
        int type = ComplexFieldUnsupported;
        std::string str;
        long long i = 0;
        bool b = false;
        std::string data;
        std::vector<std::string> list;
    };

    void ingest(const TagLib::List<TagLib::VariantMap> &maps) {
        for (auto mi = maps.begin(); mi != maps.end(); ++mi) {
            std::vector<Field> fields;
            const TagLib::VariantMap &m = *mi;
            for (auto fi = m.begin(); fi != m.end(); ++fi) {
                Field field;
                field.key = fi->first.to8Bit(true);
                const TagLib::Variant &v = fi->second;
                switch (v.type()) {
                case TagLib::Variant::String:
                    field.type = ComplexFieldString;
                    field.str = v.toString().to8Bit(true);
                    break;
                case TagLib::Variant::Bool:
                    field.type = ComplexFieldBool;
                    field.b = v.toBool();
                    break;
                case TagLib::Variant::Int:
                case TagLib::Variant::UInt:
                case TagLib::Variant::LongLong:
                case TagLib::Variant::ULongLong:
                    field.type = ComplexFieldInt;
                    field.i = v.toLongLong();
                    break;
                case TagLib::Variant::ByteVector: {
                    field.type = ComplexFieldData;
                    const TagLib::ByteVector bv = v.toByteVector();
                    field.data.assign(bv.data(), bv.size());
                    break;
                }
                case TagLib::Variant::StringList: {
                    field.type = ComplexFieldStringList;
                    const TagLib::StringList sl = v.toStringList();
                    for (auto si = sl.begin(); si != sl.end(); ++si)
                        field.list.push_back(si->to8Bit(true));
                    break;
                }
                default:
                    // Double, ByteVectorList, Map, Void: not modeled by
                    // ComplexValue -> surfaced as .unsupported.
                    field.type = ComplexFieldUnsupported;
                    break;
                }
                fields.push_back(std::move(field));
            }
            maps_.push_back(std::move(fields));
        }
    }

    std::vector<std::vector<Field>> maps_;
};

// Accumulates a List<VariantMap> from Swift. Call startMap() before each map,
// then the typed setters; finish() flushes the last map. StringList fields are
// assembled across repeated addStringListItem() calls, then merged on flush.
class ComplexPropertyBuilder {
public:
    void startMap() { flush(); haveCur_ = true; }
    void setString(const char *key, const char *val) {
        cur_.insert(TagLib::String(key, TagLib::String::UTF8),
                    TagLib::Variant(TagLib::String(val, TagLib::String::UTF8)));
    }
    void setInt(const char *key, long long val) {
        cur_.insert(TagLib::String(key, TagLib::String::UTF8), TagLib::Variant(val));
    }
    void setBool(const char *key, bool val) {
        cur_.insert(TagLib::String(key, TagLib::String::UTF8), TagLib::Variant(val));
    }
    void setData(const char *key, const char *bytes, unsigned int len) {
        cur_.insert(TagLib::String(key, TagLib::String::UTF8),
                    TagLib::Variant(TagLib::ByteVector(bytes, len)));
    }
    void addStringListItem(const char *key, const char *val) {
        lists_[TagLib::String(key, TagLib::String::UTF8)]
            .append(TagLib::String(val, TagLib::String::UTF8));
    }
    void finish() { flush(); }
    const TagLib::List<TagLib::VariantMap> &list() const { return list_; }

private:
    void flush() {
        if (!haveCur_) return;
        for (auto it = lists_.begin(); it != lists_.end(); ++it)
            cur_.insert(it->first, TagLib::Variant(it->second));
        list_.append(cur_);
        cur_ = TagLib::VariantMap();
        lists_ = TagLib::Map<TagLib::String, TagLib::StringList>();
        haveCur_ = false;
    }

    TagLib::VariantMap cur_;
    TagLib::Map<TagLib::String, TagLib::StringList> lists_;
    TagLib::List<TagLib::VariantMap> list_;
    bool haveCur_ = false;
};

// Apply a builder's list to a file under `key` (free function -- see
// applyProperties for the inout-FileRef rationale), then save() to persist.
inline bool applyComplexProperties(TagLib::FileRef &ref, const char *key,
                                   const ComplexPropertyBuilder &builder) {
    if (ref.isNull()) return false;
    return ref.setComplexProperties(key, builder.list());
}

// Round-trip a builder's list straight back through ComplexPropertyAccess with
// no file involved. Exercises the full value-type crossing for every variant
// type ComplexValue maps -- including int/bool/StringList, which no format
// actually persists via complex properties.
inline ComplexPropertyAccess
complexPropertiesRoundtrip(const ComplexPropertyBuilder &builder) {
    return ComplexPropertyAccess(builder.list());
}

// A one-field sample whose value is a Double -- a Variant type ComplexValue does
// not model -- so it decodes as .unsupported. Exists to verify that path.
inline ComplexPropertyAccess complexPropertyUnsupportedSample() {
    TagLib::VariantMap m;
    m.insert(TagLib::String("dbl"), TagLib::Variant(3.5));
    TagLib::List<TagLib::VariantMap> maps;
    maps.append(m);
    return ComplexPropertyAccess(maps);
}

} // namespace TagLibInterop

#endif /* TAGLIB_INTEROP_H */
