# Deployable to any container host (Railway, Render, Fly.io, AWS, ...).
FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
WORKDIR /app
ENV PORT=3000
EXPOSE 3000
CMD ["/app/bin/server"]
