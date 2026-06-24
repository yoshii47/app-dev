// users テーブルへのアクセス（認証情報: email, password_hash）
const pool = require('../db/pool');

// email でユーザーを1件検索（重複チェック・ログイン時に使う）
async function findUserByEmail(email) {
  const result = await pool.query(
    'SELECT * FROM users WHERE email = $1',
    [email]
  );
  return result.rows[0]; // 見つからなければ undefined
}

// 新規ユーザーを作成し、作られた id を返す
async function createUser(email, passwordHash) {
  const result = await pool.query(
    'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id',
    [email, passwordHash]
  );
  return result.rows[0].id;
}

module.exports = { findUserByEmail, createUser };
