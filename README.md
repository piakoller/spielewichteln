# Spiele-Wichteln

Eine kleine Webseite zum Wichteln von Gesellschaftsspielen:

- Die Organisatorin erstellt eine Runde und schickt **einen Einladungslink** an alle.
- Jede Person tritt mit ihrem Namen bei und bekommt einen **persönlichen Link**. Dort trägt sie ein, welche Spiele sie schon hat, und kann Wünsche notieren.
- Paare stellen sich gegenseitig als Partner/in ein (eine Person reicht) und **ziehen sich nie**.
- Die Organisatorin zieht. Danach sieht jede Person auf ihrem persönlichen Link, wen sie beschenkt, welche Spiele diese Person schon hat und ob ein bestimmtes Spiel schon im Regal steht.
- Das Ergebnis bleibt geheim, auch vor der Organisatorin.

Die Seite besteht aus einer HTML-Datei (`index.html`) und einer kostenlosen Supabase-Datenbank.

## Einrichten (ca. 15 Minuten)

### 1. Datenbank bei Supabase

1. Auf <https://supabase.com> ein kostenloses Konto erstellen und ein neues Projekt anlegen (Region z. B. Frankfurt oder Zürich).
2. Links **SQL Editor** öffnen, den ganzen Inhalt von `supabase/schema.sql` einfügen und **Run** klicken.
3. Unter **Project Settings > API** (oder **API Keys**) zwei Werte kopieren:
   - die **Project URL** (`https://….supabase.co`)
   - den **anon**- bzw. **publishable**-Key
4. Beide in `config.js` eintragen. Den `service_role`- bzw. `secret`-Key **nie** eintragen.

Hinweis: Kostenlose Supabase-Projekte werden nach etwa einer Woche ohne Nutzung pausiert. Im Dashboard lassen sie sich mit einem Klick wieder starten.

### 2. Webseite hosten

**Variante A: Netlify Drop (am einfachsten)**

1. Auf <https://app.netlify.com/drop> gehen und den ganzen Ordner `spielewichteln` ins Fenster ziehen. Den Unterordner `dev` kannst du vorher weglassen.
2. Mit einem kostenlosen Netlify-Konto bleibt die Seite dauerhaft online. Ohne Konto wird sie nach einer Stunde gelöscht.
3. Unter **Site configuration** kannst du den Namen ändern, z. B. `unser-spielewichteln.netlify.app`.

**Variante B: GitHub Pages**

1. Den Ordner als Repository auf GitHub hochladen.
2. Unter **Settings > Pages** den Branch `main` und den Ordner `/ (root)` wählen.

Ist das Repository öffentlich, ist auch `config.js` öffentlich. Das ist so vorgesehen: Der anon-Key erlaubt nur die Funktionen in `schema.sql`, und jede davon verlangt einen geheimen Link.

### 3. Loslegen

1. Die Seite öffnen und **Runde erstellen** klicken.
2. Den **Organisations-Link** gut aufbewahren, z. B. als Lesezeichen.
3. Den **Einladungslink** in den Gruppenchat schicken.
4. Wenn alle dabei sind und ihre Spiele eingetragen haben, auf der Organisationsseite **Wichtel ziehen** klicken.
5. Allen sagen, dass sie ihren persönlichen Link öffnen sollen.

Hat jemand seinen persönlichen Link verloren, findest du ihn auf der Organisationsseite unter **Bearbeiten**. Wer ihn öffnet, sieht allerdings die Ziehung dieser Person. Wer seinen Link im selben Browser schon einmal geöffnet hat, findet ihn auf der Startseite unter **Deine Runden**.

## Sicherheit in Kürze

- Die Tabellen sind für die Webseite gesperrt. Die Seite ruft nur Funktionen auf, und jede verlangt einen geheimen Code: den Einladungscode, den persönlichen Link oder den Organisations-Link.
- Mit dem persönlichen Link sieht man nur die eigene Zuteilung. Die Organisationsseite zeigt keine Zuteilungen.
- Wer den Organisations-Link hat, kann Personen entfernen und die Ziehung zurücksetzen. Teile ihn deshalb nicht.

## Lokal testen (optional)

Ohne Supabase, mit einer lokalen Datenbank in der conda-Umgebung `wichtel`:

```bash
conda create -n wichtel -c conda-forge nodejs postgresql -y
bash dev/start-local.sh
```

Danach <http://localhost:8787> öffnen. Der Testserver ersetzt `config.js` automatisch durch die lokale Datenbank.
