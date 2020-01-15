module.exports = {
  servers: {
    one: {
      host: 'coauthor.xn--mxac.cc',
      username: 'meteorapp',
      opts: {
        port: 30
      }
    }
  },

  meteor: {
    name: 'coauthor',
    path: '.',
    servers: {
      one: {}
    },
    docker: {
      image: 'abernix/meteord:node-8.15.1-base'
    },
    buildOptions: {
      serverOnly: true
    },
    env: {
      ROOT_URL: 'https://coauthor.xn--mxac.cc',
      PORT: 3001,
      MAIL_URL: false
    },
    deployCheckWaitTime: 30,
    deployCheckPort: 80,
    enableUploadProgressBar: true
  },

  mongo: {
    oplog: true,
    port: 27017,
    servers: {
      one: {},
    },
  },

  // Run 'npm install' before deploying, to ensure packages are up-to-date
  hooks: {
    'pre.deploy': {
      localCommand: 'npm install'
    }
  },
};
