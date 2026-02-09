FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -N install -q
COPY spring-petclinic-config-server/pom.xml spring-petclinic-config-server/
RUN mvn dependency:go-offline -f spring-petclinic-config-server/pom.xml -q || true
COPY spring-petclinic-config-server/src spring-petclinic-config-server/src
RUN mvn package -f spring-petclinic-config-server/pom.xml -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/spring-petclinic-config-server/target/*.jar app.jar
EXPOSE 8888
ENV SPRING_PROFILES_ACTIVE=docker
ENTRYPOINT ["java", "-jar", "app.jar"]
