//プロファイル全件取得
const pool = require('../db/pool');

async function getAllProfiles() {
  const result = await pool.query('SELECT * FROM profiles'); 
  return result.rows;
}

module.exports = { getAllProfiles };
