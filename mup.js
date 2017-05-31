module.exports = {
  servers: {
    one: {
      host: 'coauthor.ulb.ac.be',
      username: 'meteorapp'
    }
  },

  meteor: {
    name: 'coauthor',
    path: '..',
    servers: {
      one: {}
    },
    docker: {
      image: 'abernix/meteord:base' ,
      imagePort: 3001
    },
    buildOptions: {
      serverOnly: true,
      buildLocation: '/tmp/coauthor-build'
    },
    env: {
      ROOT_URL: 'https://coauthor.ulb.ac.be',
      PORT: 3001,
      MAIL_URL: 'smtp://smtp.ulb.ac.be:587',
      MONGO_URL: 'mongodb://localhost/meteor'
    },
    deployCheckWaitTime: 150,
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
};
