#!/bin/bash
set -ex
docker build -t joedefen/whisper-cuda-12 .
docker tag joedefen/whisper-cuda-12 joedefen/whisper-cuda-12:latest
docker push joedefen/whisper-cuda-12:latest
