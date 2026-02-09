FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -N install -q
COPY spring-petclinic-api-gateway/pom.xml spring-petclinic-api-gateway/
RUN mvn dependency:go-offline -f spring-petclinic-api-gateway/pom.xml -q || true
COPY spring-petclinic-api-gateway/src spring-petclinic-api-gateway/src
RUN mvn package -f spring-petclinic-api-gateway/pom.xml -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/spring-petclinic-api-gateway/target/*.jar app.jar
EXPOSE 8081
ENV SPRING_PROFILES_ACTIVE=docker
ENTRYPOINT ["java", "-jar", "app.jar"]
