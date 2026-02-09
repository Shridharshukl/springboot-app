FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -N install -q
COPY spring-petclinic-discovery-server/pom.xml spring-petclinic-discovery-server/
RUN mvn dependency:go-offline -f spring-petclinic-discovery-server/pom.xml -q || true
COPY spring-petclinic-discovery-server/src spring-petclinic-discovery-server/src
RUN mvn package -f spring-petclinic-discovery-server/pom.xml -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/spring-petclinic-discovery-server/target/*.jar app.jar
EXPOSE 8761
ENV SPRING_PROFILES_ACTIVE=docker
ENTRYPOINT ["java", "-jar", "app.jar"]
