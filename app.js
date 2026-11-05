const express = require('express')
const errorhandler = require('errorhandler')
const mongoose = require('mongoose')
const logger = require('morgan')
const cors = require('cors')
require('dotenv').config()
const swaggerUi = require('swagger-ui-express')
const helmet = require('helmet')
const swaggerDocument = require('./swagger.json')

const isProduction = process.env.NODE_ENV === 'production'
const isTest = process.env.NODE_ENV === 'test'
const isDevelopment = process.env.NODE_ENV === 'development'

const app = express()

app.use(helmet())
app.use(cors())

app.use(logger('dev'))
app.use(express.json())
app.use(express.urlencoded({ extended: false }))
mongoose.set('useNewUrlParser', true)
mongoose.set('useCreateIndex', true)
mongoose.set('useUnifiedTopology', true)

if (!isProduction) {
  app.use(errorhandler())
}

const mongoUri = isTest
  ? (process.env.MONGODB_URI_TEST || null)
  : (process.env.MONGODB_URI || null)

if (mongoUri && process.env.NODE_ENV !== 'test_unit') {
  mongoose.connect(mongoUri, {
    useNewUrlParser: true,
    useUnifiedTopology: true,
    serverSelectionTimeoutMS: 3000
  }).catch(err => {
    console.warn(`[WARN] MongoDB initial connection failed: ${err.message}`)
  })
}

if (isDevelopment && mongoUri) {
  mongoose.set('debug', true)
}

require('./models/User')
require('./models/Article')
require('./models/Comment')
require('./config/passport')

app.get('/health', (req, res) => {
  const mongoStatus = mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'
  const isHealthy = mongoStatus === 'connected'

  return res.status(isHealthy ? 200 : 503).json({
    status: isHealthy ? 'UP' : 'DOWN',
    timestamp: new Date().toISOString(),
    uptime: Math.floor(process.uptime()),
    service: 'conduit-api',
    checks: {
      database: mongoStatus
    }
  })
})

app.use(require('./routes'))
app.use('/', swaggerUi.serve, swaggerUi.setup(swaggerDocument))

/// catch 404 and forward to error handler
app.use(function (req, res, next) {
  const err = new Error('Not Found')
  err.status = 404
  next(err)
})

/// error handlers

// development error handler
// will print stacktrace
if (!isProduction) {
  app.use(function (err, req, res, next) {
    console.log(err.stack)

    res.status(err.status || 500)

    res.json({
      errors: {
        message: err.message,
        error: err
      }
    })
  })
}

// production error handler
// no stacktraces leaked to user
app.use(function (err, req, res, next) {
  res.status(err.status || 500)
  res.json({
    errors: {
      message: err.message,
      error: {}
    }
  })
})

module.exports = app
