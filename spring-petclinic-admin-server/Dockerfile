FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -N install -q
COPY spring-petclinic-admin-server/pom.xml spring-petclinic-admin-server/
RUN mvn dependency:go-offline -f spring-petclinic-admin-server/pom.xml -q || true
COPY spring-petclinic-admin-server/src spring-petclinic-admin-server/src
RUN mvn package -f spring-petclinic-admin-server/pom.xml -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/spring-petclinic-admin-server/target/*.jar app.jar
EXPOSE 9090
ENV SPRING_PROFILES_ACTIVE=docker
ENTRYPOINT ["java", "-jar", "app.jar"]
