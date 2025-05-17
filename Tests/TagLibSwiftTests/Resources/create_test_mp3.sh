#!/bin/bash

# 1초 길이의 무음 MP3 파일 생성
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 1 -q:a 9 -acodec libmp3lame test.mp3

# 메타데이터 추가
ffmpeg -i test.mp3 -metadata title="Original Title" \
    -metadata artist="Original Artist" \
    -metadata album="Original Album" \
    -metadata genre="Original Genre" \
    -metadata year="2023" \
    -metadata track="1" \
    -codec copy test_with_metadata.mp3

# 원본 파일 삭제
rm test.mp3

# 최종 파일 이름 변경
mv test_with_metadata.mp3 test.mp3 