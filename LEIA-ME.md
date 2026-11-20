# Lava Jato online: passo a passo (100% gratuito)

Esta versão guarda tudo num banco de dados online (Supabase). O cliente entra no próprio celular com e-mail e senha, a recuperação de senha chega por e-mail, e o administrativo e o caixa funcionam de qualquer aparelho. Você precisa de 3 contas gratuitas: **Supabase** (banco e login), **Brevo** (envio dos e-mails) e um lugar para **publicar o site** (Netlify, Cloudflare Pages ou GitHub Pages).

Arquivos: `index.html` (o sistema), `supabase.sql` (o banco) e este guia.

## 1. Criar o banco (Supabase)
1. Crie uma conta em supabase.com e clique em **New project**. Escolha a região **South America (São Paulo)** e anote a senha do banco.
2. No menu, abra **SQL Editor**, cole todo o conteúdo de `supabase.sql` e clique em **Run**. Se aparecer erro, copie a mensagem e me mande.

## 2. Criar o administrador
1. Em **Authentication > Users**, clique em **Add user > Create new user**. Informe o e-mail e a senha do dono e marque **Auto Confirm User**.
2. No **SQL Editor**, rode (troque pelo e-mail que você criou):
   `insert into admins (id) select id from auth.users where email = 'SEU_EMAIL_AQUI';`

## 3. Ligar o sistema ao banco
1. Em **Project Settings > API**, copie a **Project URL** e a **chave pública** (chamada *anon* ou *publishable*). Nunca use a chave *service_role* ou *secret*.
2. Abra o `index.html` em um editor de texto e cole os dois valores no começo do script, no lugar de `COLE_AQUI...`. Confira também o número `ZAP` (WhatsApp do lava-jato, com 55 e DDD, só números).

## 4. Publicar o site (grátis)
Escolha um: **Netlify** (app.netlify.com/drop, arraste a pasta com o `index.html`), **Cloudflare Pages** (envio direto de arquivos) ou **GitHub Pages**. Você recebe um endereço, por exemplo `https://seu-lava-jato.netlify.app`.

## 5. Informar o endereço ao Supabase
Em **Authentication > URL Configuration**, coloque o endereço do site em **Site URL** e também em **Redirect URLs**. Sem isso, o link do e-mail de nova senha não volta para o seu site.

## 6. Enviar e-mails de verdade (obrigatório)
O envio de e-mail embutido do Supabase manda só 2 e-mails por hora e só para a equipe do projeto, então **não serve para clientes**. Configure um provedor gratuito:
1. Crie uma conta no **Brevo** (ou Resend), verifique o e-mail remetente e gere as credenciais SMTP.
2. No Supabase, abra **Authentication > Emails > SMTP Settings**, ligue **Enable custom SMTP** e preencha remetente, host, porta, usuário e senha do provedor.
3. Teste pedindo “Esqueci minha senha” com o e-mail de um cliente de teste.

Dica: se quiser que o cadastro funcione sem confirmar e-mail, desative **Confirm email** em **Authentication**, no provedor de e-mail. Com a opção ligada, o cliente precisa abrir o link enviado antes de entrar.

## Como usar
- **Cliente:** abre o endereço do site, cria o cadastro e vê os cartões dos veículos, o andamento na fila e o histórico.
- **Administrativo:** toque 5 vezes rápido em “LAVA JATO” no topo e entre com o e-mail e a senha do administrador. Abas: Fila, Caixa, Clientes, Serviços e Resumo.
- **Cliente cadastrado no balcão:** depois ele cria a própria senha em “Cadastre-se”, usando o mesmo telefone e a mesma data de nascimento.

## Limites do plano gratuito (confira os valores atuais)
- O projeto do Supabase **pausa após 7 dias sem uso** e precisa ser reativado no painel. Com uso diário, isso não acontece.
- Não há backups diários no plano gratuito. Exporte as tabelas em CSV (Table Editor) de vez em quando.
- Há limites de tamanho (cerca de 500 MB) e de e-mails por dia no provedor escolhido, suficientes para um lava-jato pequeno.
- **WhatsApp automático não é gratuito** (a API oficial é paga). Por isso o botão “Pedir ajuda pelo WhatsApp” só abre a conversa com o lava-jato, e a equipe responde.
- Os dados são pessoais (nome, telefone, nascimento): guarde as senhas do painel com cuidado e use só para o lava-jato (LGPD).
