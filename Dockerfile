FROM ghcr.io/gmeligio/flutter-android:3.50.0

WORKDIR /workspace/frame_walk

COPY --chown=flutter:flutter frame_walk/pubspec.yaml frame_walk/pubspec.lock ./
RUN flutter pub get

COPY --chown=flutter:flutter frame_walk/ ./

# Pass the key as a BuildKit secret when map tiles are needed. The secret and
# generated local.properties file are removed in the same build layer.
RUN --mount=type=secret,id=maps_api_key \
    if [ -f /run/secrets/maps_api_key ]; then \
      printf '\nMAPS_API_KEY=%s\n' "$(< /run/secrets/maps_api_key)" >> android/local.properties; \
    fi; \
    flutter build apk --debug --android-skip-build-dependency-validation; \
    rm -f android/local.properties

FROM alpine:3.22

COPY --from=0 /workspace/frame_walk/build/app/outputs/flutter-apk/app-debug.apk /FrameWalk-debug.apk

ENTRYPOINT ["cp", "/FrameWalk-debug.apk", "/out/FrameWalk-debug.apk"]
