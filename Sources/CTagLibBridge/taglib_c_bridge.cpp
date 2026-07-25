#include "taglib_c_bridge.h"
#include <taglib/taglib.h>
#include <taglib/fileref.h>
#include <taglib/tag.h>
#include <string>
#include <memory>

namespace {
    // Per-thread error buffer: each thread reads back the error it set, and the
    // returned c_str() stays valid until the same thread next mutates it. This
    // avoids the cross-thread clobbering and use-after-unlock races a shared
    // global buffer would have.
    thread_local std::string g_lastError;

    void set_error(const std::string& error) {
        g_lastError = error;
    }
}

const char* taglib_get_last_error(void) {
    return g_lastError.c_str();
}

void taglib_clear_error(void) {
    g_lastError.clear();
}

struct TagLib_File {
    TagLib::FileRef* fileRef;
    TagLib::Tag* tag;
    std::string title;
    std::string artist;
    std::string album;
    std::string genre;
};

TagLib_File* taglib_file_new(const char* path) {
    try {
        // unique_ptr owns the wrapper until we hand it off, so an exception
        // thrown while constructing the FileRef cannot leak it.
        auto file = std::make_unique<TagLib_File>();
        file->fileRef = new TagLib::FileRef(path);

        if (file->fileRef->isNull()) {
            set_error("Failed to open file: " + std::string(path));
            delete file->fileRef;
            return nullptr;
        }

        file->tag = file->fileRef->tag();
        if (!file->tag) {
            set_error("Failed to get tag from file: " + std::string(path));
            delete file->fileRef;
            return nullptr;
        }

        return file.release();
    } catch (const std::exception& e) {
        set_error("Exception while opening file: " + std::string(e.what()));
        return nullptr;
    }
}

void taglib_file_free(TagLib_File* file) {
    if (file) {
        delete file->fileRef;
        delete file;
    }
}

int taglib_file_save(TagLib_File* file) {
    if (!file || !file->fileRef) {
        set_error("Invalid file handle");
        return 0;
    }
    
    try {
        if (file->fileRef->save()) {
            return 1;
        }
        set_error("Failed to save file");
        return 0;
    } catch (const std::exception& e) {
        set_error("Exception while saving file: " + std::string(e.what()));
        return 0;
    }
}

int taglib_file_is_valid(TagLib_File* file) {
    return (file && file->fileRef && !file->fileRef->isNull()) ? 1 : 0;
}

const char* taglib_file_get_title(TagLib_File* file) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return "";
    }
    file->title = file->tag->title().to8Bit();
    return file->title.c_str();
}

const char* taglib_file_get_artist(TagLib_File* file) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return "";
    }
    file->artist = file->tag->artist().to8Bit();
    return file->artist.c_str();
}

const char* taglib_file_get_album(TagLib_File* file) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return "";
    }
    file->album = file->tag->album().to8Bit();
    return file->album.c_str();
}

const char* taglib_file_get_genre(TagLib_File* file) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return "";
    }
    file->genre = file->tag->genre().to8Bit();
    return file->genre.c_str();
}

unsigned int taglib_file_get_year(TagLib_File* file) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return 0;
    }
    return file->tag->year();
}

unsigned int taglib_file_get_track(TagLib_File* file) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return 0;
    }
    return file->tag->track();
}

void taglib_file_set_title(TagLib_File* file, const char* title) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return;
    }
    file->tag->setTitle(title);
}

void taglib_file_set_artist(TagLib_File* file, const char* artist) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return;
    }
    file->tag->setArtist(artist);
}

void taglib_file_set_album(TagLib_File* file, const char* album) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return;
    }
    file->tag->setAlbum(album);
}

void taglib_file_set_genre(TagLib_File* file, const char* genre) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return;
    }
    file->tag->setGenre(genre);
}

void taglib_file_set_year(TagLib_File* file, unsigned int year) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return;
    }
    file->tag->setYear(year);
}

void taglib_file_set_track(TagLib_File* file, unsigned int track) {
    if (!file || !file->tag) {
        set_error("Invalid file handle");
        return;
    }
    file->tag->setTrack(track);
} 