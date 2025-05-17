#include "taglib_c_bridge.h"
#include <taglib/taglib.h>
#include <taglib/fileref.h>
#include <taglib/tag.h>
#include <string>

struct TagLib_File {
    TagLib::FileRef* fileRef;
    TagLib::Tag* tag;
    std::string* errorMessage;
};

TagLib_File* taglib_file_new(const char* path) {
    auto file = new TagLib_File();
    file->fileRef = new TagLib::FileRef(path);
    file->tag = file->fileRef->tag();
    file->errorMessage = new std::string();
    return file;
}

void taglib_file_free(TagLib_File* file) {
    if (file) {
        delete file->fileRef;
        delete file->errorMessage;
        delete file;
    }
}

int taglib_file_save(TagLib_File* file) {
    return file->fileRef->save() ? 1 : 0;
}

const char* taglib_file_get_title(TagLib_File* file) {
    return file->tag->title().toCString();
}

const char* taglib_file_get_artist(TagLib_File* file) {
    return file->tag->artist().toCString();
}

const char* taglib_file_get_album(TagLib_File* file) {
    return file->tag->album().toCString();
}

const char* taglib_file_get_genre(TagLib_File* file) {
    return file->tag->genre().toCString();
}

unsigned int taglib_file_get_year(TagLib_File* file) {
    return file->tag->year();
}

unsigned int taglib_file_get_track(TagLib_File* file) {
    return file->tag->track();
}

void taglib_file_set_title(TagLib_File* file, const char* title) {
    file->tag->setTitle(title);
}

void taglib_file_set_artist(TagLib_File* file, const char* artist) {
    file->tag->setArtist(artist);
}

void taglib_file_set_album(TagLib_File* file, const char* album) {
    file->tag->setAlbum(album);
}

void taglib_file_set_genre(TagLib_File* file, const char* genre) {
    file->tag->setGenre(genre);
}

void taglib_file_set_year(TagLib_File* file, unsigned int year) {
    file->tag->setYear(year);
}

void taglib_file_set_track(TagLib_File* file, unsigned int track) {
    file->tag->setTrack(track);
} 