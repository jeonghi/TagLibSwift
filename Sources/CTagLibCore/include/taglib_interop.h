#ifndef TAGLIB_INTEROP_H
#define TAGLIB_INTEROP_H

// Thin inline C++ helpers that smooth over Swift/C++ interop limitations with
// TagLib's public API. These are NOT a C ABI bridge -- they take and return
// TagLib C++ types by value and are consumed directly from the TagLibSwiftCxx
// interop module. They exist because:
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

#include "taglib/fileref.h"
#include "taglib/tfile.h"
#include "taglib/tag.h"
#include "taglib/tstring.h"
#include "taglib/audioproperties.h"
#include "taglib/mpegfile.h"
#include "taglib/id3v2tag.h"
#include "taglib/id3v2frame.h"

namespace TagLibInterop {

// Construct a FileRef from a UTF-8 path (default read-style resolved in C++).
inline TagLib::FileRef openFile(const char *path) {
    return TagLib::FileRef(path);
}

// AudioProperties bitrate in kbps, or -1 if unavailable.
inline int bitrate(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    return p ? p->bitrate() : -1;
}

// AudioProperties length in milliseconds, or -1 if unavailable.
inline int lengthMs(const TagLib::FileRef &ref) {
    const TagLib::AudioProperties *p = ref.audioProperties();
    return p ? p->lengthInMilliseconds() : -1;
}

// The title tag as a TagLib::String value (empty if no tag). Returned by value
// so the Swift caller can exercise TagLib::String -> Swift.String conversion.
inline TagLib::String title(const TagLib::FileRef &ref) {
    const TagLib::Tag *t = ref.tag();
    return t ? t->title() : TagLib::String();
}

// A COPY of the file's ID3v2 frame list (List<Frame*>), for exercising List<T>
// in Swift. The copied pointers dangle after this returns, so the caller must
// only inspect list metadata (size/isEmpty), never dereference the frames.
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
