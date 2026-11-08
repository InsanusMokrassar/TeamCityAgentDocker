# TeamCity Agent Docker

Образ **поверх официального `jetbrains/teamcity-agent:latest`** для Java/Kotlin,
Android и браузерных тестов. Платформы: `linux/amd64` и `linux/arm64` (RPi 5 с
64-битной ОС). Образ не заменяет механизм запуска TeamCity собственным скриптом.

## Что установлено

- TeamCity-агент, JDK 21, Git и остальные инструменты официального образа.
- Python 3, GnuPG, curl, CA certificates, zip/unzip и xz.
- Node.js 24 LTS и npm из официального multiarch-образа Node.
- Настоящий **Chromium** и Linux-библиотеки из подписанного
  [PPA XtraDeb](https://launchpad.net/~xtradeb/+archive/ubuntu/apps) для Ubuntu
  24.04. Не Google Chrome, не Chrome for Testing и не Ubuntu Snap.
- Обе команды: `chromium` и `chromium-browser`; `CHROME_BIN` задан автоматически.
- Android Command-line Tools **21.0 / 15641748**, SDK platform **37.0**, Build Tools
  **37.0.0**, platform-tools и принятые SDK licenses.
- `ANDROID_HOME` и `ANDROID_SDK_ROOT`: `/opt/android-sdk`, SDK доступен на запись
  пользователю `buildagent`. Для существующих проверок API 37 также доступен путь
  `/opt/android-sdk/platforms/android-37`.

Chromium запускается с `--no-sandbox --disable-dev-shm-usage` для контейнерных
CI-тестов. Не требуется Snap, privileged-контейнер или установка пакетов во время
сборки проекта. Версия Chromium обновляется при ежедневной пересборке из apt.
PPA ограничен pinning-правилами для пакетов Chromium; ключ проверяется по полному
fingerprint. Образ намеренно проверяет Ubuntu 24.04: при смене ОС в upstream
сборка остановится, а не подключит репозиторий другой ОС.

### Особенности ARM64

Java, Node, Chromium и агент работают нативно. Официальный Android SDK пока
содержит ряд x86 Linux host tools. Поэтому в ARM64-варианте:

- `aapt2` заменён нативным **9.5.1-16666295 из официального Google Maven**;
- задано `ORG_GRADLE_PROJECT_android.aapt2FromMavenOverride`, чтобы старые AGP,
  включая 9.1.x, не скачивали x86-вариант `aapt2`;
- `aapt`, `aidl`, `zipalign`, `adb` и `fastboot` используют нативные пакеты Ubuntu.
  Их версии отличаются от версий в Google SDK ZIP.

Command-line Tools зафиксированы на Java-версии `sdkmanager`: более новый архив
23.0 заменяет его launcher-ом нативного Android CLI, что не подходит для
одинаковой установки на amd64 и arm64.

Smoke test действительно компилирует и связывает Android-ресурсы на каждой
архитектуре. NDK, эмулятор Android, аппаратные тесты и сборка произвольного
проекта целиком этим тестом не покрываются. Остальные нативные утилиты Google SDK
не объявляются ARM-совместимыми только по факту наличия файлов.

## Замена текущего агента

После первой публикации заменить **только имя образа** в существующем запуске:

```yaml
image: insanusmokrassar/teamcity-agent:latest
# либо фиксированная дата: insanusmokrassar/teamcity-agent:YYYY-MM-DD
```

Оставить прежние `SERVER_URL`, `AGENT_NAME`, `AGENT_TOKEN`, сети и volumes,
включая `/data/teamcity_agent/conf` и `/opt/buildagent/*`. Сохранённый `conf`
сохраняет авторизацию агента. По умолчанию он продолжает работать как
`buildagent` (UID/GID 1000). `CMD`, `ENTRYPOINT`, `WORKDIR` и volumes наследуются
от официального образа; root используется только при сборке Dockerfile.

Этот репозиторий сам по себе **не меняет и не перезапускает существующий агент**.

## Локальная проверка без секретов и публикации

Нужны Docker с Buildx, Bash, Python 3 и Git на машине, где выполняется проверка:

```bash
./scripts/test-local.sh
```

Скрипт собирает и загружает образ в локальный Docker, запускает smoke test от
`buildagent` и сверяет контракт запуска с официальным образом. Он не делает
`docker login` и `docker push`.

```bash
PLATFORM=linux/amd64 ./scripts/test-local.sh
PLATFORM=linux/arm64 ./scripts/test-local.sh  # нативно на RPi 5 / другом ARM64
./scripts/test-local.sh --no-cache          # полная свежая пересборка
```

На другой архитектуре требуется заранее настроенная Docker/QEMU-эмуляция.
Скрипт не меняет binfmt хоста автоматически. GitHub Actions проверяет обе
архитектуры на **нативных** runners, без QEMU.

Smoke test проверяет Java 21-компиляцию, инструменты, права на SDK, настоящую
компиляцию/link Android-ресурсов и выполнение JavaScript в headless Chromium.

Параметры Dockerfile переопределяются через `--build-arg`, например:

```bash
./scripts/test-local.sh --build-arg ANDROID_API=37.0
```

`TEAMCITY_AGENT_IMAGE` позволяет зафиксировать официальный базовый tag/digest.
Он должен включать обе Linux-архитектуры при multiarch-сборке; например, не все
теги с суффиксом `-linux` включают ARM64. Обновление Java/Ubuntu в upstream
проверяется smoke test, а не предполагается незаметно совместимым.

## GitHub Actions и Docker Hub

Два независимых workflow:

1. **Build and test (no publishing)** — push в `main`, pull request или ручной
   запуск. Собирает и тестирует обе архитектуры. **Секреты не нужны.**
2. **Daily Docker Hub publication** — ежедневно в **02:43 UTC / 08:43 Омск**
   либо вручную. Снова собирает обе архитектуры с `--pull` и без кеша, проверяет,
   затем публикует именно проверенные образы и собирает multiarch manifest.

В Settings → Secrets and variables → Actions → Repository secrets добавить
те же имена, что используются в
[JenkinsDocker](https://github.com/InsanusMokrassar/JenkinsDocker/blob/master/.github/workflows/docker-publish.yml):

| Secret | Значение |
| --- | --- |
| `DOCKER_LOGIN` | Docker Hub login с правом записи в `insanusmokrassar/teamcity-agent` |
| `DOCKER_PASSWORD` | Docker Hub access token с правом Read & Write |

Имена совпадают с референсом, но repository secrets **не копируются GitHub
автоматически между репозиториями**. До их добавления publication workflow
корректно пропускает публикацию; проверки работают независимо. После добавления
запустить publication workflow вручную или дождаться следующего расписания.
Создать публичный Docker Hub repository `insanusmokrassar/teamcity-agent`, если
аккаунт не создаёт его автоматически при первом push.

Теги:

- `insanusmokrassar/teamcity-agent:YYYY-MM-DD` — multiarch, дата начала workflow в UTC;
- `insanusmokrassar/teamcity-agent:latest` — последняя успешная multiarch-публикация;
- `YYYY-MM-DD-amd64` и `YYYY-MM-DD-arm64` — соответствующие проверенные варианты.

Повторный запуск в тот же день обновляет теги этой даты. Общие теги обновляются
только после успеха обеих архитектур; ошибка одной не продвигает `latest`.
GitHub может задерживать cron и отключает scheduled workflow в неактивных
публичных репозиториях после 60 дней; при этом его нужно включить снова.
