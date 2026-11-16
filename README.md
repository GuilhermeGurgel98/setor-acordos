# Setor de Acordos D'Freire

App do Setor de Acordos e Atendimento (site estático).

- `index.html`: o app inteiro.
- `config.js`: endereço e chave pública do Supabase (projeto `setor-acordos`).
- `schema.sql`: tabelas e regras de acesso do banco.

Login por e-mail e senha (Supabase Auth). Novos integrantes entram por convite enviado no painel do Supabase (Authentication > Users > Invite user).
Administradores ficam na tabela `acordos_admins`.
