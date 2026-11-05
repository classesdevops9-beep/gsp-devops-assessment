process.env.NODE_ENV = 'test_unit'
const assert = require('assert')
const http = require('http')
const app = require('../app')
const mongoose = require('mongoose')

async function runTests () {
  console.log('--- Running Application Verification Tests ---')

  // 1. Verify models exist
  assert(mongoose.model('User'), 'User model must be registered')
  assert(mongoose.model('Article'), 'Article model must be registered')
  assert(mongoose.model('Comment'), 'Comment model must be registered')
  console.log('✓ All Mongoose models registered successfully')

  // 2. Test User password hashing & compare with bcryptjs
  const User = mongoose.model('User')
  const testUser = new User({
    username: 'devopsuser',
    email: 'devops@example.com'
  })

  // Test bcryptjs hashing directly via model method
  const bcrypt = require('bcryptjs')
  const salt = bcrypt.genSaltSync(10)
  testUser.hash = bcrypt.hashSync('SuperSecret123!', salt)

  await new Promise((resolve, reject) => {
    testUser.comparePassword('SuperSecret123!', (err, isMatch) => {
      if (err) return reject(err)
      assert.strictEqual(isMatch, true, 'Valid password must match hash')
      resolve()
    })
  })

  await new Promise((resolve, reject) => {
    testUser.comparePassword('WrongPassword!', (err, isMatch) => {
      if (err) return reject(err)
      assert.strictEqual(isMatch, false, 'Invalid password must not match hash')
      resolve()
    })
  })
  console.log('✓ Password hashing and verification working correctly')

  // 3. Test HTTP /health endpoint
  const server = http.createServer(app)
  await new Promise(resolve => server.listen(0, resolve))
  const port = server.address().port

  const healthData = await new Promise((resolve, reject) => {
    http.get(`http://localhost:${port}/health`, res => {
      // In isolated test without MongoDB, readyState is 0, so /health returns 503 degraded
      assert(res.statusCode === 503 || res.statusCode === 200, `Expected 200 or 503, got ${res.statusCode}`)
      let raw = ''
      res.on('data', chunk => { raw += chunk })
      res.on('end', () => {
        try {
          resolve(JSON.parse(raw))
        } catch (e) {
          reject(e)
        }
      })
    }).on('error', reject)
  })

  assert(healthData.status === 'UP' || healthData.status === 'DOWN', 'Health status should be UP or DOWN')
  assert(healthData.service === 'conduit-api', 'Service name should match')
  assert(healthData.checks && healthData.checks.database, 'Database health check field must exist')
  console.log(`✓ /health endpoint verified (status: ${healthData.status}, db: ${healthData.checks.database})`)

  await new Promise(resolve => server.close(resolve))
  console.log('--- All Tests Passed Successfully! ---')
}

runTests().catch(err => {
  console.error('Test suite failed:', err)
  process.exit(1)
})
