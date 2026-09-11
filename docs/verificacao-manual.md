# Verificação manual

O que a suíte automatizada não alcança, e por quê. Rode isto antes de dar
uma versão por boa.

A suíte Python roda sem hardware, sem root e sem sessão gráfica — é o que
a torna útil em qualquer máquina. O preço é que ela não vê o que só existe
num ambiente de verdade: um host de bandeja vivo no barramento, e a roda
do mouse sobre um painel desenhado pelo ambiente.

> **Nota histórica.** Este arquivo teria uma seção sobre `pkexec`, do
> helper que rodaria como root. O helper foi cancelado junto com a ação de
> forçar perfis (ver `interface.md` §6.1), e **o projeto não tem mais
> nenhum código privilegiado**. Não há o que verificar ali.

---

## 1. O ícone na bandeja

**Por que não é automatizável:** o `StatusNotifierItem` só existe se
houver um host SNI vivo no barramento de sessão, e o scroll é um gesto do
mouse sobre um painel desenhado pelo ambiente. Um teste sem sessão
gráfica não tem onde girar a roda.

**Antes de começar**, confirme que há host e watcher:

```bash
busctl --user list | grep -i statusnotifier
```

Tem de aparecer `org.kde.StatusNotifierWatcher` e um
`org.kde.StatusNotifierHost-*`.

**O que fazer, e o que esperar:**

| gesto | o que tem de acontecer |
|---|---|
| passar o mouse | tooltip com perfil, as duas rotações e a temperatura |
| clique esquerdo | a janela abre |
| clique direito | menu com os perfis disponíveis, ventoinha, Abrir e Sair |
| clique do meio | alterna entre o perfil atual e o anterior |
| roda para cima | sobe um perfil; o ícone muda |
| roda para baixo | desce um perfil |

**O teste que importa, e que só existe na bateria:** tire o cabo, ponha
no `Econômico` e gire para cima. Tem de ir direto ao **Equilibrado**,
pulando o `Silencioso`, e girar mais não pode fazer nada — nem mudar o
perfil, nem mostrar erro. É o buraco da escada da spec §2.8.

**Reabertura obrigatória:** escolha “Ventoinha automática” e abra o menu
novamente com o botão direito. As opções devem continuar presentes.
Reabra o aplicativo pelo lançador e confirme que permanece apenas um ícone.

**Se o clique direito não abrir menu:** confira a propriedade `Menu` do
SNI e `GetLayout` em `/MenuBar`, interface `com.canonical.dbusmenu`.
O protocolo está implementado e coberto em `test_tray_dbus.py`, com um
barramento privado e sysfs falso. Esses testes não substituem o clique no
painel real. Uma chamada direta a `ContextMenu()` também não o substitui.

**Autostart:** após encerrar e iniciar a sessão, o ícone deve aparecer sem
abrir o aplicativo. A entrada em `/etc/xdg/autostart` foi restaurada em
2026-09-06; a verificação após essa restauração continua pendente.

**Se o ícone não aparecer:** o app caiu para `QSystemTrayIcon` (menu sim,
scroll não) ou para janela direta. Confirme no terminal, que imprime qual
bandeja subiu.

**Sobre o tooltip:** o `ToolTip` do padrão SNI é uma struct `(sa(iiay)ss)`,
cujo empacotamento em PySide6 daria muito trabalho para pouco. O Plasma cai
no `Title` quando o `ToolTip` está vazio, então o texto vai no `Title`.
Confira aqui se ele aparece com as três linhas, e não truncado numa só.
