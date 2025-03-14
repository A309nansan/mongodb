FROM mongodb/mongodb-community-server:6.0.19-ubuntu2204

USER root

# 시간 동기화
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

USER mongodb
