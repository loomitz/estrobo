#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSet>
#include <QTimer>
#include <QTextStream>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (app.arguments().size() != 2) return 2;
    const QString engine = app.arguments().at(1);
    QProcess process;
    QTimer ticker, deadline;
    int ticks = 0, ticksAtStart = 0, epoch = 0;
    bool closing = false, killed = false, killScheduled = false;
    bool sawAuthenticating = false, sawSynchronizing = false;
    QSet<int> pending;
    QByteArray buffer;
    auto log = [](const QJsonObject &value) {
        QTextStream(stdout) << QJsonDocument(value).toJson(QJsonDocument::Compact) << Qt::endl;
    };
    auto fail = [&](const QString &reason) {
        log({{"event", "failure"}, {"reason", reason}, {"epoch", epoch}});
        process.kill();
        app.exit(1);
    };
    auto send = [&](int id, const QString &command) {
        if (process.state() != QProcess::Running) return false;
        pending.insert(id);
        const auto bytes = QJsonDocument(QJsonObject{{"id", id}, {"command", command}}).toJson(QJsonDocument::Compact) + '\n';
        return process.write(bytes) == bytes.size();
    };
    ticker.setInterval(10);
    QObject::connect(&ticker, &QTimer::timeout, [&] { ++ticks; });
    deadline.setSingleShot(true);
    QObject::connect(&deadline, &QTimer::timeout, [&] { fail("bounded harness deadline"); });
    QObject::connect(&process, &QProcess::readyReadStandardError, [&] {
        QTextStream(stderr) << process.readAllStandardError();
    });
    QObject::connect(&process, &QProcess::errorOccurred, [&](QProcess::ProcessError error) {
        if (!(epoch == 1 && killed && error == QProcess::Crashed)) fail(process.errorString());
    });
    QObject::connect(&process, &QProcess::readyReadStandardOutput, [&] {
        buffer += process.readAllStandardOutput();
        while (buffer.contains('\n')) {
            const int end = buffer.indexOf('\n');
            const auto line = buffer.left(end);
            buffer.remove(0, end + 1);
            QJsonParseError parseError;
            const auto doc = QJsonDocument::fromJson(line, &parseError);
            if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
                fail("non-JSON engine output");
                return;
            }
            const auto event = doc.object();
            log({{"event", "engine-event"}, {"epoch", epoch}, {"payload", event}});
            const auto kind = event.value("event").toString();
            if (kind == "hello") {
                if (event.value("protocol").toInt() != 1) { fail("protocol mismatch"); return; }
                ticksAtStart = ticks;
                if (!send(epoch == 0 ? 1 : 101, "start")) { fail("start rejected"); return; }
            } else if (kind == "phase") {
                const auto phase = event.value("phase").toString();
                sawAuthenticating |= phase == "authenticating";
                sawSynchronizing |= phase == "synchronizing";
                if (epoch == 1 && phase == "scanning" && !killScheduled) {
                    killScheduled = true;
                    QTimer::singleShot(100, [&] { killed = true; process.kill(); });
                }
            } else if (kind == "result") {
                const int id = event.value("id").toInt();
                if (!pending.remove(id)) { fail("unexpected or duplicate result"); return; }
                if (epoch == 1) { fail("interrupted operation falsely completed"); return; }
                if (id == 1) {
                    if (!event.value("ok").toBool() || event.value("phase") != "ready" ||
                        !sawAuthenticating || !sawSynchronizing || ticks - ticksAtStart < 10) {
                        fail("real session did not become ready with responsive Qt loop"); return;
                    }
                    if (!send(2, "adjust")) { fail("adjust rejected"); return; }
                } else if (id == 2) {
                    if (!event.value("ok").toBool() || event.value("pending").toInt(-1) != 0) {
                        fail("real controller apply failed"); return;
                    }
                    if (!send(3, "unknown")) { fail("error probe rejected"); return; }
                } else if (id == 3) {
                    if (event.value("ok").toBool() || event.value("error") != "unknown command") {
                        fail("invalid command falsely succeeded"); return;
                    }
                    closing = true;
                    if (!send(4, "shutdown")) { fail("shutdown rejected"); return; }
                } else if (id == 4) {
                    if (!event.value("ok").toBool() || event.value("phase") != "shutdown") {
                        fail("missing graceful shutdown result"); return;
                    }
                    process.closeWriteChannel(); // EOF releases the engine input reader.
                }
            }
        }
    });
    QObject::connect(&process, &QProcess::finished, [&](int code, QProcess::ExitStatus status) {
        if (epoch == 0) {
            if (!closing || code != 0 || status != QProcess::NormalExit || !pending.isEmpty()) {
                fail("graceful exit failed or requests unresolved"); return;
            }
            log({{"event", "graceful-close-pass"}, {"qtTicks", ticks}});
            epoch = 1;
            buffer.clear();
            process.start(engine, QStringList{});
        } else {
            if (!killed || !pending.contains(101) || (status == QProcess::NormalExit && code == 0)) {
                fail("forced interruption not detected"); return;
            }
            const auto invalidated = pending.size();
            pending.clear(); // this process generation is invalid; never retry its request
            if (send(102, "adjust")) { fail("accepted work on dead engine"); return; }
            log({{"event", "QT_SWIFT_BRIDGE_PASS"}, {"qtTicks", ticks},
                 {"invalidatedPending", static_cast<int>(invalidated)}, {"automaticRetries", 0},
                 {"limits", "synthetic transport; no durable-journal/BLE proof"}});
            deadline.stop();
            app.exit(0);
        }
    });
    ticker.start();
    deadline.start(40000);
    process.start(engine, QStringList{});
    return app.exec();
}
