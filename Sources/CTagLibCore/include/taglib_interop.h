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
//  * TagLib::MPEG::File is non-copyable (deleted copy ctor), so it cannot be
//    held in a Swift value. id3v2FrameList() owns it for the call's duration.
//
//  * TagLib::PropertyMap is a Map<String, StringList>. Rather than rely on the
//    (uncertain) Swift import of std::map/std::list iterators, the small
//    copyable helper classes PropertyMapAccess / PropertyMapBuilder flatten the
//    crossing into value-returning, index-addressed accessors. Both are concrete
//    copyable value types, so they import on the value-type path (no reference
//    types => the iOS 13 / macOS 10.15 floor is preserved).

#include <string>

#include "taglib/fileref.h"
#include "taglib/tfile.h"
#include "taglib/tag.h"
#include "taglib/tstring.h"
#include "taglib/tstringlist.h"
#include "taglib/tpropertymap.h"
#include "taglib/audioproperties.h"
#include "taglib/mpegfile.h"
#include "taglib/id3v2tag.h"
#include "taglib/id3v2frame.h"

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
        for (auto it = map_.begin(); it != map_.end(); ++it) {
            keys_.append(it->first);
        }
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
inline bool applyProperties(TagLib::FileRef &ref, const PropertyMapBuilder &builder) {
    if (ref.isNull()) return false;
    ref.setProperties(builder.map());
    return true;
}

// ---------------------------------------------------------------------------
// Legacy spike helper retained so the original interop slice test still builds.
// A COPY of the file's ID3v2 frame list (List<Frame*>). The copied pointers
// dangle after this returns; the caller must only inspect list metadata.
// ---------------------------------------------------------------------------

inline TagLib::ID3v2::FrameList id3v2FrameList(const char *path) {
    TagLib::MPEG::File file(path);
    if (!file.isValid()) {
        return TagLib::ID3v2::FrameList();
    }
    const TagLib::ID3v2::Tag *tag = file.ID3v2Tag(false);
    if (!tag) {
        return TagLib::ID3v2::FrameList();
    }
    return tag->frameList();
}

} // namespace TagLibInterop

#endif /* TAGLIB_INTEROP_H */
