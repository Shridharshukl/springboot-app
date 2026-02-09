FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -N install -q
COPY spring-petclinic-vets-service/pom.xml spring-petclinic-vets-service/
RUN mvn dependency:go-offline -f spring-petclinic-vets-service/pom.xml -q || true
COPY spring-petclinic-vets-service/src spring-petclinic-vets-service/src
RUN mvn package -f spring-petclinic-vets-service/pom.xml -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/spring-petclinic-vets-service/target/*.jar app.jar
EXPOSE 8081
ENV SPRING_PROFILES_ACTIVE=docker
ENTRYPOINT ["java", "-jar", "app.jar"]
