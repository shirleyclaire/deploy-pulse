# Why we copy a pre-built jar instead of running Maven inside Docker:
# Building inside Docker would require downloading the entire Maven dependency
# cache on every image build, making builds slow and fragile in CI environments
# with limited network access. Instead, Maven runs once in CI (or locally via
# "mvn package -DskipTests"), producing a single fat-jar in target/. Docker's
# only job is to package and run that artifact -- keeping the image small,
# the build fast, and the two concerns cleanly separated.

FROM eclipse-temurin:17-jre

# Build-time metadata (passed via --build-arg in CI)
ARG APP_VERSION=unknown
ARG GIT_SHA=unknown
ARG BUILD_TIME=unknown

# Promote build args to runtime environment variables so the Spring Boot app
# can read them through InfoService's env map.
ENV APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA} \
    BUILD_TIME=${BUILD_TIME}

# Create a non-root user and group for security best practice.
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --no-create-home appuser

WORKDIR /app

# Copy only the runnable fat-jar produced by spring-boot-maven-plugin.
# The glob excludes the thin *.original artifact that Maven also writes.
COPY target/deploy-pulse-*.jar app.jar

# Adjust ownership so the non-root user can read the jar.
RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8080

# -XX:MaxRAMPercentage=70 lets the JVM use up to 70 % of the container's
# memory limit instead of defaulting to 25 % of the host RAM.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70", "-jar", "/app/app.jar"]
