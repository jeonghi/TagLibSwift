#ifndef taglib_c_bridge_h
#define taglib_c_bridge_h

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TagLib_File TagLib_File;

// Error handling
const char* taglib_get_last_error(void);
void taglib_clear_error(void);

// File operations
TagLib_File* taglib_file_new(const char* path);
void taglib_file_free(TagLib_File* file);
int taglib_file_save(TagLib_File* file);
int taglib_file_is_valid(TagLib_File* file);

// Tag operations
const char* taglib_file_get_title(TagLib_File* file);
const char* taglib_file_get_artist(TagLib_File* file);
const char* taglib_file_get_album(TagLib_File* file);
const char* taglib_file_get_genre(TagLib_File* file);
unsigned int taglib_file_get_year(TagLib_File* file);
unsigned int taglib_file_get_track(TagLib_File* file);

void taglib_file_set_title(TagLib_File* file, const char* title);
void taglib_file_set_artist(TagLib_File* file, const char* artist);
void taglib_file_set_album(TagLib_File* file, const char* album);
void taglib_file_set_genre(TagLib_File* file, const char* genre);
void taglib_file_set_year(TagLib_File* file, unsigned int year);
void taglib_file_set_track(TagLib_File* file, unsigned int track);

#ifdef __cplusplus
}
#endif

#endif /* taglib_c_bridge_h */ 