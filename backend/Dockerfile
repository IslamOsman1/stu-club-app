FROM dart:stable
ENV PUB_CACHE=/opt/pub-cache
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY bin ./bin
COPY tool ./tool
RUN mkdir -p /app/data /app/backups && useradd -u 10001 -m stuclub && chown -R stuclub:stuclub /app /opt/pub-cache
ENV STU_HOST=0.0.0.0 PORT=8080 STU_STORAGE=sqlite STU_DATA=/app/data/club.json
USER stuclub
EXPOSE 8080
CMD ["dart", "run", "bin/server.dart"]
