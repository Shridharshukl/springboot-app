FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -N install -q
COPY spring-petclinic-visits-service/pom.xml spring-petclinic-visits-service/
RUN mvn dependency:go-offline -f spring-petclinic-visits-service/pom.xml -q || true
COPY spring-petclinic-visits-service/src spring-petclinic-visits-service/src
RUN mvn package -f spring-petclinic-visits-service/pom.xml -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/spring-petclinic-visits-service/target/*.jar app.jar
EXPOSE 8081
ENV SPRING_PROFILES_ACTIVE=docker
ENTRYPOINT ["java", "-jar", "app.jar"]
