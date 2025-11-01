const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send("Hello from Node.js API 🚀 (v2)");
});

app.listen(3000, () => console.log('Node.js app running on port 3000'));

const sql = require('mssql');

const config = {
  connectionString: process.env.SQL_CONNECTION_STRING
};

async function testConnection() {
  try {
    const pool = await sql.connect(config.connectionString);
    const result = await pool.request().query('SELECT name FROM sys.databases');
    console.log('Connected. Databases:', result.recordset.map(r => r.name));
    await pool.close();
  } catch (err) {
    console.error('DB connection failed:', err);
  }
}

testConnection();