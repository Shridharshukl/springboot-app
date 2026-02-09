FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -N install -q
COPY spring-petclinic-customers-service/pom.xml spring-petclinic-customers-service/
RUN mvn dependency:go-offline -f spring-petclinic-customers-service/pom.xml -q || true
COPY spring-petclinic-customers-service/src spring-petclinic-customers-service/src
RUN mvn package -f spring-petclinic-customers-service/pom.xml -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/spring-petclinic-customers-service/target/*.jar app.jar
EXPOSE 8081
ENV SPRING_PROFILES_ACTIVE=docker
ENTRYPOINT ["java", "-jar", "app.jar"]
